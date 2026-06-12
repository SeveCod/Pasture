import Foundation

/// Núcleo testeable del servidor MCP (ADR-004): una línea JSON-RPC entrante →
/// una línea de respuesta, o `nil` si es notificación / línea vacía.
///
/// SIN I/O de proceso: el executable la cablea a `FileHandle`. Nunca lanza —
/// todo fallo se traduce en una línea de error JSON-RPC o en `isError` de tool
/// (SEC-M12: una request inválida no tumba la conexión).
public struct MCPDispatcher: Sendable {
    private let config: MCPServerConfig

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
            return successLine(id: id, result: InitializeResult())

        case "ping":
            return successLine(id: id, result: EmptyResult())

        case "tools/list":
            return successLine(id: id, result: MCPTools.catalog())

        case "tools/call":
            let result = MCPTools.run(params: request.params, config: config)
            return successLine(id: id, result: result)

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
