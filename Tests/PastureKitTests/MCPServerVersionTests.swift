import Testing
import Foundation
@testable import PastureKit

/// v1.8 — la versión del servidor MCP sube a 1.8.0 y se refleja en el
/// `serverInfo.version` del `initialize`.
@Suite("MCPProtocol — server version 1.8.0")
struct MCPServerVersionTests {

    @Test("serverVersion is 1.8.0")
    func serverVersionIs180() {
        #expect(MCPProtocol.serverVersion == "1.8.0")
    }

    @Test("initialize surfaces serverInfo.version 1.8.0")
    func initializeSurfacesVersion() throws {
        let line = try InitializeResult().mcpLine()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        #expect(json.object?["serverInfo"]?.object?["version"]?.stringValue == "1.8.0")
    }
}
