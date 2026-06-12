import Foundation

/// Constantes del protocolo MCP y códigos de error JSON-RPC.
public enum MCPProtocol {
    public static let version = "2025-06-18"
    public static let serverName = "pasture-mcp"
    public static let serverVersion = "1.5.0"

    // Códigos JSON-RPC para errores de PROTOCOLO (no de tool — D6 / ADR-006).
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
}

/// Respuesta de `initialize`. `capabilities.tools` DEBE estar presente aunque
/// vacío (gotcha 3): se serializa como `{}`, nunca ausente.
public struct InitializeResult: Encodable {
    public struct Capabilities: Encodable {
        public let tools: [String: JSONValue]
    }
    public struct ServerInfo: Encodable {
        public let name: String
        public let version: String
    }
    public let protocolVersion: String
    public let capabilities: Capabilities
    public let serverInfo: ServerInfo

    public init() {
        self.protocolVersion = MCPProtocol.version
        self.capabilities = Capabilities(tools: [:])
        self.serverInfo = ServerInfo(
            name: MCPProtocol.serverName,
            version: MCPProtocol.serverVersion)
    }
}

/// Resultado vacío para `ping` (objeto `{}`).
public struct EmptyResult: Encodable {
    public init() {}
}

/// Resultado de `tools/call`. `isError:true` = fallo de TOOL (lo ve el modelo y
/// se recupera). Distinto del objeto `error` JSON-RPC (fallo de PROTOCOLO).
/// `warning` (D4 / SEC-M8) es no bloqueante: solo se serializa si hay valor.
public struct ToolCallResult: Encodable {
    public struct TextContent: Encodable {
        public let type = "text"
        public let text: String

        private enum CodingKeys: String, CodingKey { case type, text }
    }
    public let content: [TextContent]
    public let isError: Bool
    public let warning: String?

    public init(content: [TextContent], isError: Bool, warning: String? = nil) {
        self.content = content
        self.isError = isError
        self.warning = warning
    }

    public static func ok(_ text: String, warning: String? = nil) -> ToolCallResult {
        ToolCallResult(content: [TextContent(text: text)], isError: false, warning: warning)
    }

    public static func failure(_ text: String) -> ToolCallResult {
        ToolCallResult(content: [TextContent(text: text)], isError: true, warning: nil)
    }
}
