import Foundation

/// Primitiva MCP `prompts`: cada template del vault (fichero con `{{VAR}}` o
/// bloques) se expone como prompt parametrizado. En Claude Code aparecen como
/// slash-commands con argumentos; el cliente pide exactamente los valores que el
/// template necesita.
///
/// Solo lectura (SEC-M11): `prompts/get` renderiza en MEMORIA con
/// `TemplateEngine.render` (single-pass — un valor de argumento nunca se
/// re-parsea como sintaxis de template) y jamás escribe a disco. El texto
/// renderizado pasa por `SecretScanner` post-sustitución (ADR-QW-002); el aviso
/// enmascarado (familia + fichero, nunca el valor) viaja en `description`
/// (SEC-M8/D4, informativo, no bloqueante).
///
/// `prompts/get` no es una tool: sus fallos (prompt inexistente, argumento
/// required ausente, argumento sobredimensionado) son errores JSON-RPC de
/// protocolo (`MCPRequestError`, -32602), no `isError` de tool (SEC-M12).
public enum MCPPrompts {

    // MARK: — Tipos de resultado

    public struct PromptsListResult: Encodable {
        public struct PromptArgument: Encodable {
            public let name: String
            public let description: String
            public let required: Bool
        }
        public struct PromptDescriptor: Encodable {
            public let name: String
            public let description: String
            public let arguments: [PromptArgument]
        }
        public let prompts: [PromptDescriptor]
    }

    public struct GetPromptResult: Encodable {
        public struct Message: Encodable {
            public struct TextContent: Encodable {
                public let type = "text"
                public let text: String
                private enum CodingKeys: String, CodingKey { case type, text }
            }
            public let role: String
            public let content: TextContent
        }
        /// Opcional: cuando hay secretos en el render, lleva el resumen enmascarado.
        public let description: String?
        public let messages: [Message]
    }

    // MARK: — Fichero-template resuelto

    /// Un template del vault con su nombre de prompt estable. `content` se lee una
    /// sola vez por request (sin estado entre requests, ADR-005).
    struct PromptFile {
        let name: String
        let relativePath: String
        let url: URL
        let content: String
    }

    /// Nombre de prompt = ruta relativa sin `.md`, con `/` → `__`.
    /// (p. ej. `proyecto/spec.md` → `proyecto__spec`).
    static func promptName(forRelativePath relativePath: String) -> String {
        var base = relativePath
        if base.hasSuffix(".md") { base.removeLast(3) }
        return base.replacingOccurrences(of: "/", with: "__")
    }

    /// Enumera los ficheros del vault que son templates (tienen variables o
    /// bloques), leyendo su contenido. Resuelve colisiones de nombre: la segunda
    /// ruta que colisione tras la sustitución se descarta con log a stderr.
    static func templateFiles(config: MCPServerConfig) -> [PromptFile] {
        let entries = MCPTools.enumerateVaultFiles(vaultRoot: config.vaultRoot)
        var result: [PromptFile] = []
        var seenNames = Set<String>()

        for entry in entries {
            guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else { continue }
            // AC#6: filtro = variables O bloques (misma semántica que hasTemplateVars).
            guard TemplateEngine.hasVariables(in: content) || TemplateEngine.hasBlocks(in: content) else {
                continue
            }
            let name = promptName(forRelativePath: entry.relativePath)
            guard !seenNames.contains(name) else {
                logToStderr("prompt name collision, dropping '\(entry.relativePath)' (name '\(name)' already taken)")
                continue
            }
            seenNames.insert(name)
            result.append(PromptFile(
                name: name, relativePath: entry.relativePath, url: entry.url, content: content))
        }
        return result
    }

    // MARK: — prompts/list

    public static func list(config: MCPServerConfig) -> PromptsListResult {
        let prompts = templateFiles(config: config).map { file -> PromptsListResult.PromptDescriptor in
            let variables = TemplateEngine.extractVariables(from: file.content)
            let arguments = variables.map { argument(for: $0) }
            return PromptsListResult.PromptDescriptor(
                name: file.name,
                description: "Rendered from vault template \(file.relativePath)",
                arguments: arguments)
        }
        return PromptsListResult(prompts: prompts)
    }

    /// Traduce una `TemplateVariable` a un argumento de prompt MCP.
    /// - required = sin valor por defecto (un default lo hace opcional).
    /// - `.list` documenta la convención de valores separados por comas.
    static func argument(for variable: TemplateVariable) -> PromptsListResult.PromptArgument {
        let description: String
        switch variable.kind {
        case .list:
            description = "Comma-separated list of values (each item is iterated in the template)."
        case .scalar:
            if variable.defaultValue.isEmpty {
                description = "Text value."
            } else {
                description = "Optional. Defaults to '\(variable.defaultValue)'."
            }
        }
        // Un `.list` viene de `#each` y nunca trae default → required.
        let required = variable.defaultValue.isEmpty
        return PromptsListResult.PromptArgument(
            name: variable.name, description: description, required: required)
    }

    // MARK: — prompts/get

    public static func get(params: JSONValue?, config: MCPServerConfig) -> Result<GetPromptResult, MCPRequestError> {
        guard let name = params?.object?["name"]?.stringValue, !name.isEmpty else {
            return .failure(.invalidParams("se requiere el argumento 'name'"))
        }

        // Re-enumeración: el mapeo name→ruta se resuelve aquí (sin estado entre
        // requests). Un nombre descartado por colisión no resolverá aquí tampoco.
        guard let file = templateFiles(config: config).first(where: { $0.name == name }) else {
            return .failure(.invalidParams("prompt no encontrado: \(name)"))
        }

        let providedArguments = params?.object?["arguments"]?.object ?? [:]
        let variables = TemplateEngine.extractVariables(from: file.content)

        // Construir los valores finales: default salvo que el cliente dé un valor.
        var resolved: [TemplateVariable] = []
        for var variable in variables {
            let key = variable.name
            let provided = providedArguments[key]?.stringValue
            let isRequired = variable.defaultValue.isEmpty

            if isRequired {
                // AC#10: argumento required AUSENTE → error de protocolo.
                guard let value = provided else {
                    return .failure(.invalidParams("falta el argumento required: \(key)"))
                }
                if value.count > MCPLimits.maxPromptArgumentLength {
                    return .failure(.invalidParams("argumento demasiado largo: \(key)"))
                }
                variable.value = value
            } else {
                // Opcional: valor no vacío lo sustituye; vacío u omitido → default.
                if let value = provided, !value.isEmpty {
                    if value.count > MCPLimits.maxPromptArgumentLength {
                        return .failure(.invalidParams("argumento demasiado largo: \(key)"))
                    }
                    variable.value = value
                }
                // else: variable.value ya es defaultValue (init de TemplateVariable).
            }
            resolved.append(variable)
        }

        // Render single-pass: los valores no se re-parsean como sintaxis; hereda
        // maxNestingDepth/maxIterations/maxOutputCharacters del motor.
        let rendered = TemplateEngine.render(file.content, with: resolved)

        // SEC-M5: rechazar renders gigantes antes de serializar.
        if rendered.utf8.count > MCPLimits.maxResponseBytes {
            return .failure(.invalidParams("prompt renderizado demasiado grande"))
        }

        // SEC-M8 (D4): warning enmascarado sobre el contenido YA renderizado
        // (ADR-QW-002). Nunca el valor del secreto. `nil` si está limpio.
        let warning = MCPTools.secretWarning(fileName: file.relativePath, content: rendered)

        let result = GetPromptResult(
            description: warning,
            messages: [
                GetPromptResult.Message(
                    role: "user",
                    content: GetPromptResult.Message.TextContent(text: rendered)),
            ])
        return .success(result)
    }

    // MARK: — Log (SEC-M7: stderr, nunca stdout)

    private static func logToStderr(_ message: String) {
        FileHandle.standardError.write(Data("[pasture-mcp] \(message)\n".utf8))
    }
}
