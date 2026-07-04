import Foundation

/// Catálogo y ejecución de las cuatro tools de solo lectura (D2: una sola
/// `feed_context`). Toda la lógica de dominio se reutiliza de PastureKit
/// (`FileLibrary`, `PathValidator`, `MDFile.matches`, `ContextBuilder`).
public enum MCPTools {

    // MARK: — Tipos del catálogo (tools/list)

    /// Esquema de entrada de una tool. `type` siempre `"object"` (gotcha 4).
    public struct InputSchema: Encodable {
        public let type = "object"
        public let properties: [String: PropertySchema]
        public let required: [String]

        private enum CodingKeys: String, CodingKey { case type, properties, required }
    }

    /// Esquema de una propiedad. `items` solo para arrays.
    public struct PropertySchema: Encodable {
        public let type: String
        public let items: ItemSchema?

        public init(type: String, items: ItemSchema? = nil) {
            self.type = type
            self.items = items
        }
    }

    public struct ItemSchema: Encodable {
        public let type: String
    }

    public struct ToolDefinition: Encodable {
        public let name: String
        public let description: String
        public let inputSchema: InputSchema
    }

    public struct ToolsListResult: Encodable {
        public let tools: [ToolDefinition]
    }

    // MARK: — Catálogo

    /// Catálogo para `tools/list`. Las cuatro tools, cada una con
    /// `inputSchema.type == "object"` (gotcha 4).
    public static func catalog() -> ToolsListResult {
        ToolsListResult(tools: [
            ToolDefinition(
                name: "list_files",
                description: "List all Markdown files and collections in the Pasture vault (~/.pasture/), read-only.",
                inputSchema: InputSchema(properties: [:], required: [])),
            ToolDefinition(
                name: "read_file",
                description: "Return the raw contents of a single file in the vault, by path relative to ~/.pasture/.",
                inputSchema: InputSchema(
                    properties: ["path": PropertySchema(type: "string")],
                    required: ["path"])),
            ToolDefinition(
                name: "search",
                description: "Find files in the vault whose name or content contains a literal, case-insensitive query.",
                inputSchema: InputSchema(
                    properties: ["query": PropertySchema(type: "string")],
                    required: ["query"])),
            ToolDefinition(
                name: "feed_context",
                description: "Assemble vault context using Pasture's Feed format from a collection or a list of files.",
                inputSchema: InputSchema(
                    properties: [
                        "collection": PropertySchema(type: "string"),
                        "files": PropertySchema(type: "array", items: ItemSchema(type: "string")),
                    ],
                    required: [])),
        ])
    }

    // MARK: — Ejecución (tools/call)

    /// Despacho de `tools/call`. Devuelve `ToolCallResult` (`isError` de tool,
    /// nunca lanza). Un nombre de tool inválido es error de TOOL, no de protocolo.
    public static func run(params: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        guard let name = params?.object?["name"]?.stringValue else {
            return .failure("falta el nombre de la tool")
        }
        let arguments = params?.object?["arguments"]

        switch name {
        case "list_files":
            return listFiles(config: config)
        case "read_file":
            return readFile(arguments: arguments, config: config)
        case "search":
            return search(arguments: arguments, config: config)
        case "feed_context":
            return feedContext(arguments: arguments, config: config)
        default:
            return .failure("tool desconocida: \(name)")
        }
    }

    // MARK: — Implementación de tools (rellenadas por TDD en bloques 4-7)

    static func listFiles(config: MCPServerConfig) -> ToolCallResult {
        // Enumeración SOLO vía FileLibrary (SEC-M2): ya filtra ocultos y symlinks.
        // Síncrono: usamos mdFiles/realSubdirectories directamente, sin el puente
        // async de load(at:) (ADR-005, loop secuencial).
        let files = enumerateVaultFiles(vaultRoot: config.vaultRoot)

        guard !files.isEmpty else {
            return .ok("(vault is empty: no Markdown files found)")
        }

        let lines = files.map { entry -> String in
            if let collection = entry.collection {
                return "\(entry.relativePath)  [collection: \(collection)]"
            }
            return "\(entry.relativePath)  [root]"
        }
        return .ok(lines.joined(separator: "\n"))
    }

    /// Fichero del vault con su ruta relativa y colección. Vía FileLibrary,
    /// que filtra ocultos y symlinks (SEC-M2). Raíz + subdirectorios de 1 nivel.
    struct VaultFile {
        let url: URL
        let relativePath: String
        let collection: String?
    }

    static func enumerateVaultFiles(vaultRoot: URL) -> [VaultFile] {
        var entries: [VaultFile] = []
        let basePath = vaultRoot.standardizedFileURL.path

        func relative(_ url: URL) -> String {
            let full = url.standardizedFileURL.path
            if full.hasPrefix(basePath + "/") {
                return String(full.dropFirst(basePath.count + 1))
            }
            return url.lastPathComponent
        }

        for file in FileLibrary.mdFiles(in: vaultRoot) {
            entries.append(VaultFile(url: file.url, relativePath: relative(file.url), collection: nil))
        }
        for subdir in FileLibrary.realSubdirectories(in: vaultRoot) {
            let collectionName = subdir.lastPathComponent
            for file in FileLibrary.mdFiles(in: subdir) {
                entries.append(VaultFile(
                    url: file.url, relativePath: relative(file.url), collection: collectionName))
            }
        }
        return entries
    }

    static func readFile(arguments: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        guard let path = arguments?.object?["path"]?.stringValue, !path.isEmpty else {
            return .failure("se requiere el argumento 'path'")
        }

        // SEC-M1 + SEC-M2: validar ANTES de cualquier I/O, con resolución de symlinks.
        let resolved: URL
        switch MCPPathResolver.resolve(relativePath: path, vaultRoot: config.vaultRoot) {
        case .success(let url):
            resolved = url
        case .failure:
            return .failure("ruta fuera del vault")
        }

        // SEC-M5: rechazar por TAMAÑO EN DISCO antes de leer, para no materializar un
        // fichero gigante en RAM sólo para descartarlo después.
        if let onDisk = fileSizeOnDisk(resolved), onDisk > MCPLimits.maxResponseBytes {
            return .failure("fichero demasiado grande, no se puede entregar")
        }

        guard let content = try? String(contentsOf: resolved, encoding: .utf8) else {
            return .failure("fichero no encontrado")
        }

        // SEC-M5: segunda barrera exacta sobre los bytes UTF-8 ya cargados.
        if content.utf8.count > MCPLimits.maxResponseBytes {
            return .failure("fichero demasiado grande, no se puede entregar")
        }

        // SEC-M8 (D4): warning no bloqueante si hay secretos. Contenido íntegro.
        let warning = secretWarning(fileName: resolved.lastPathComponent, content: content)
        return .ok(content, warning: warning)
    }

    /// SEC-M5: tamaño en disco (bytes) de un fichero, o `nil` si no se puede leer.
    /// Permite rechazar ficheros gigantes ANTES de materializarlos en RAM.
    static func fileSizeOnDisk(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// SEC-M8 (D4): resumen enmascarado de secretos (familia + fichero), NUNCA el
    /// valor. Devuelve `nil` si el contenido está limpio. Reutiliza `SecretScanner`.
    static func secretWarning(fileName: String, content: String) -> String? {
        let result = SecretScanner.scan(fileName: fileName, content: content)
        guard !result.isEmpty else { return nil }
        let summary = result.summaryLines().joined(separator: "; ")
        return "possible secrets detected (content delivered unchanged): \(summary)"
    }

    static func search(arguments: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        guard let query = arguments?.object?["query"]?.stringValue else {
            return .failure("se requiere el argumento 'query'")
        }

        // SEC-M4: cap de longitud de query.
        if query.count > MCPLimits.maxQueryLength {
            return .failure("query demasiado larga (máximo \(MCPLimits.maxQueryLength) caracteres)")
        }

        // HU-10: query vacía NO vuelca el vault. Se intercepta ANTES de matches
        // (que devolvería true para todo). Resultado vacío con éxito.
        guard !query.isEmpty else {
            return .ok("(empty query: no results)")
        }

        let files = enumerateVaultFiles(vaultRoot: config.vaultRoot)
        var matched: [String] = []
        for entry in files {
            if matchesLiteral(query: query, fileURL: entry.url) {
                matched.append(entry.relativePath)
                // SEC-M4: cap de resultados.
                if matched.count >= MCPLimits.maxSearchResults { break }
            }
        }

        guard !matched.isEmpty else {
            return .ok("(no files match \"\(query)\")")
        }
        return .ok(matched.joined(separator: "\n"))
    }

    /// Misma semántica que `MDFile.matches` (literal, case-insensitive sobre
    /// nombre y contenido), pero leyendo el contenido ACOTADO (SEC-M4) en lugar de
    /// cargar ficheros enormes completos en RAM. El cap de 2 MB por fichero lo
    /// aplica `SecretScanner.cappedContent`, que vive en `SecretScanner.maxScanBytes`
    /// (no en `MCPLimits`): reusamos su truncado seguro de UTF-8 en vez de duplicarlo.
    static func matchesLiteral(query: String, fileURL: URL) -> Bool {
        let name = fileURL.deletingPathExtension().lastPathComponent
        if name.localizedCaseInsensitiveContains(query) { return true }
        guard let full = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        let content = SecretScanner.cappedContent(full)   // SecretScanner.maxScanBytes (2 MB)
        return content.localizedCaseInsensitiveContains(query)
    }

    static func feedContext(arguments: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        let collection = arguments?.object?["collection"]?.stringValue
        let fileNames = arguments?.object?["files"]?.arrayValue?.compactMap { $0.stringValue }

        let hasFiles = !(fileNames?.isEmpty ?? true)
        let hasCollection = !(collection?.isEmpty ?? true)

        // HU-7: ni collection ni files → error de tool.
        guard hasFiles || hasCollection else {
            return .failure("se requiere 'collection' o 'files'")
        }

        // D2: si se pasan ambos, gana 'files' (más específica).
        let selection: FeedSelection
        if hasFiles {
            selection = resolveFileList(fileNames ?? [], config: config)
        } else {
            guard let resolved = resolveCollection(collection ?? "", config: config) else {
                return .failure("colección no encontrada: \(collection ?? "")")
            }
            selection = resolved
        }

        guard !selection.entries.isEmpty else {
            return .failure("no se encontró ningún fichero para ensamblar")
        }

        // SEC-M6: ensamblado EXCLUSIVAMENTE vía ContextBuilder (misma pieza que la app).
        // D3: contenido crudo — NO se llama a TemplateEngine.render.
        let payload = ContextBuilder.build(files: selection.entries, format: config.feedFormat)

        // SEC-M5: rechazar respuestas gigantes antes de serializar.
        if payload.utf8.count > MCPLimits.maxResponseBytes {
            return .failure("contexto demasiado grande, refina la selección")
        }

        // SEC-M8 (D4): warning combinado (secretos + ficheros ausentes), no bloqueante.
        let warning = combinedWarning(selection: selection)
        return .ok(payload, warning: warning)
    }

    /// Selección resuelta para feed_context: entries en orden + avisos de ausentes.
    struct FeedSelection {
        var entries: [ContextBuilder.FileEntry]
        /// Para SEC-M8: (fileName, content) de cada entry, para el escaneo de secretos.
        var scanned: [(name: String, content: String)]
        var missing: [String]
    }

    /// HU-7: lista de ficheros por nombre. Cada uno pasa el gate de ruta
    /// (SEC-M1/M2). Los ausentes/fuera se OMITEN y se listan como aviso (no falla
    /// en bloque). Orden preservado.
    static func resolveFileList(_ names: [String], config: MCPServerConfig) -> FeedSelection {
        var entries: [ContextBuilder.FileEntry] = []
        var scanned: [(name: String, content: String)] = []
        var missing: [String] = []

        for name in names {
            switch MCPPathResolver.resolve(relativePath: name, vaultRoot: config.vaultRoot) {
            case .failure:
                missing.append(name)
            case .success(let url):
                // SEC-M5: omitir ficheros que por sí solos ya exceden el cap de respuesta,
                // sin cargarlos en RAM. El check final del payload ensamblado sigue en
                // feedContext; esto evita el pico de memoria por un único fichero gigante.
                if let onDisk = fileSizeOnDisk(url), onDisk > MCPLimits.maxResponseBytes {
                    missing.append(name)
                    continue
                }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    missing.append(name)
                    continue
                }
                // FileEntry.name SIN extensión: ContextBuilder añade ".md".
                let entryName = url.deletingPathExtension().lastPathComponent
                entries.append(ContextBuilder.FileEntry(name: entryName, content: content))
                scanned.append((name: url.lastPathComponent, content: content))
            }
        }
        return FeedSelection(entries: entries, scanned: scanned, missing: missing)
    }

    /// HU-6: colección. Devuelve `nil` si no es un subdirectorio real. Symlinks
    /// ya filtrados por FileLibrary (SEC-M2).
    static func resolveCollection(_ name: String, config: MCPServerConfig) -> FeedSelection? {
        let subdirs = FileLibrary.realSubdirectories(in: config.vaultRoot)
        guard let dir = subdirs.first(where: { $0.lastPathComponent == name }) else {
            return nil
        }
        var entries: [ContextBuilder.FileEntry] = []
        var scanned: [(name: String, content: String)] = []
        for file in FileLibrary.mdFiles(in: dir) {
            // FileEntry.name SIN extensión (MDFile.name ya viene sin ".md").
            entries.append(ContextBuilder.FileEntry(name: file.name, content: file.content))
            scanned.append((name: file.url.lastPathComponent, content: file.content))
        }
        return FeedSelection(entries: entries, scanned: scanned, missing: [])
    }

    /// SEC-M8 + HU-7: combina el aviso de secretos (familia + fichero, sin valor)
    /// y el de ficheros ausentes. `nil` si no hay nada que avisar.
    static func combinedWarning(selection: FeedSelection) -> String? {
        var parts: [String] = []

        let scanResult = SecretScanner.scan(
            selection.scanned.map { SecretScanner.Input(fileName: $0.name, content: $0.content) })
        if !scanResult.isEmpty {
            parts.append("possible secrets detected (content delivered unchanged): "
                + scanResult.summaryLines().joined(separator: "; "))
        }
        if !selection.missing.isEmpty {
            parts.append("files not found (omitted): " + selection.missing.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
}
