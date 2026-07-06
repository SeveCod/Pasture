import Foundation

/// Núcleo testeable del servidor MCP (ADR-004): una línea JSON-RPC entrante →
/// una línea de respuesta, o `nil` si es notificación / línea vacía.
///
/// SIN I/O de proceso: el executable la cablea a `FileHandle`. Nunca lanza —
/// todo fallo se traduce en una línea de error JSON-RPC o en `isError` de tool
/// (SEC-M12: una request inválida no tumba la conexión).
///
/// Es `final class` (no `struct`) para capturar el `clientInfo` del `initialize`
/// y grabarlo como procedencia de las propuestas (v1.8). `@unchecked Sendable` es
/// seguro sin cerrojo porque el executable la consume en un bucle secuencial
/// single-thread (ADR-MCP-005): una línea entra, se despacha y sale, nunca en
/// paralelo. `handle(line:)` sigue siendo la frontera testeable.
public final class MCPDispatcher: @unchecked Sendable {
    private let config: MCPServerConfig
    /// Procedencia capturada en `initialize` (o `nil` hasta entonces).
    private var clientInfo: ClientInfo?

    struct ClientInfo: Sendable, Equatable {
        let name: String

        /// SEC (v1.8): la procedencia acaba en el frontmatter de las notas
        /// promovidas; un `name` con saltos de línea inyectaría claves (H1). Se
        /// colapsa a una sola línea y se acota la longitud en el punto de ingest,
        /// además del escape en `FrontmatterWriter.setting` (defensa en profundidad).
        static let maxNameLength = 200

        init(name: String) {
            let collapsed = name
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            self.name = String(collapsed.prefix(Self.maxNameLength))
        }
    }

    /// Nombre del cliente MCP para la procedencia de las propuestas, o "unknown".
    var proposedBy: String { clientInfo?.name ?? "unknown" }

    public init(config: MCPServerConfig) {
        self.config = config
    }

    /// `nil` ⇒ no emitir nada (notificación o línea vacía).
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Decodificar. Fallo ⇒ -32700 parse error con id null.
        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: Data(trimmed.utf8)) else {
            return errorLine(id: nil, code: MCPProtocol.parseError, message: "JSON inválido")
        }

        // 2a. `id:null` explícito: es un request inválido por spec, NO una
        // notificación. Se responde -32600 con id null (no se silencia, H1).
        if request.hasExplicitNullID {
            return errorLine(id: nil, code: MCPProtocol.invalidRequest, message: "id no puede ser null")
        }

        // 2b. Notificación (sin miembro `id`) ⇒ procesar efecto (ninguno) y no responder.
        if request.isNotification {
            return nil
        }

        // A partir de aquí hay id: lo necesitamos para responder.
        guard let id = request.id else { return nil }

        // 3. Despacho por método.
        switch request.method {
        case "initialize":
            // Captura la procedencia; el proceso es single-thread (ADR-MCP-005).
            if let name = request.params?.object?["clientInfo"]?.object?["name"]?.stringValue {
                clientInfo = ClientInfo(name: name)
            }
            return successLine(id: id, result: InitializeResult())

        case "ping":
            return successLine(id: id, result: EmptyResult())

        case "tools/list":
            return successLine(id: id, result: MCPTools.catalog(includingProposals: config.allowProposals))

        case "tools/call":
            let result = MCPTools.run(params: request.params, config: config, proposedBy: proposedBy)
            return successLine(id: id, result: result)

        case "resources/list":
            return successLine(id: id, result: MCPResources.list(config: config))

        case "resources/read":
            // `resources/read` no es tool: un fallo es error de PROTOCOLO, no
            // `isError` (SEC-M12). El Result se traduce a línea de error.
            switch MCPResources.read(params: request.params, config: config) {
            case .success(let result): return successLine(id: id, result: result)
            case .failure(let error): return errorLine(id: id, code: error.code, message: error.message)
            }

        case "prompts/list":
            return successLine(id: id, result: MCPPrompts.list(config: config))

        case "prompts/get":
            switch MCPPrompts.get(params: request.params, config: config) {
            case .success(let result): return successLine(id: id, result: result)
            case .failure(let error): return errorLine(id: id, code: error.code, message: error.message)
            }

        default:
            return errorLine(
                id: id,
                code: MCPProtocol.methodNotFound,
                message: "método no soportado: \(request.method)")
        }
    }

    // MARK: — Serialización de respuestas (nunca lanza hacia el caller)

    private func successLine<R: Encodable>(id: JSONRPCID, result: R) -> String {
        let response = JSONRPCResponse(id: id, result: result)
        // mcpLine() solo lanza si el tipo no es serializable; nuestros tipos sí lo
        // son. Ante un fallo imposible degradamos a un error interno serializable.
        return (try? response.mcpLine())
            ?? fallbackErrorLine(id: id, message: "error de serialización interno")
    }

    private func errorLine(id: JSONRPCID?, code: Int, message: String) -> String {
        let response = JSONRPCErrorResponse(
            id: id,
            error: JSONRPCErrorResponse.ErrorBody(code: code, message: message))
        return (try? response.mcpLine())
            ?? fallbackErrorLine(id: id, message: message)
    }

    /// Línea de error construida a mano como último recurso (sin pasar por
    /// `Encodable`), para no devolver `nil` ante un fallo de serialización.
    private func fallbackErrorLine(id: JSONRPCID?, message: String) -> String {
        let idFragment: String
        switch id {
        case .number(let value): idFragment = "\(value)"
        case .string(let value): idFragment = "\"\(value)\""
        case .none: idFragment = "null"
        }
        return #"{"jsonrpc":"2.0","id":\#(idFragment),"error":{"code":\#(MCPProtocol.parseError),"message":"internal error"}}"#
    }
}
