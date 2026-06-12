import Testing
import Foundation
@testable import PastureKit

/// Bloque 8 del diseño: generador de configuración MCP (HU-2/3). Lógica pura,
/// testeable sin UI. El descubrimiento de la ruta (Bundle.main) vive en la app.
@Suite struct MCPConfigGeneratorTests {

    // MARK: — Claude Code (claude mcp add)

    @Test func claudeCodeCommandIncludesPathAfterSeparator() {
        let command = MCPConfigGenerator.claudeCodeCommand(
            binaryPath: "/Applications/Pasture.app/Contents/MacOS/pasture-mcp",
            feedFormat: .xml)
        #expect(command.contains("claude mcp add pasture"))
        #expect(command.contains("-- "))
        #expect(command.contains("/Applications/Pasture.app/Contents/MacOS/pasture-mcp"))
    }

    @Test func claudeCodeCommandInjectsFeedFormatEnv() {
        let command = MCPConfigGenerator.claudeCodeCommand(
            binaryPath: "/Applications/Pasture.app/Contents/MacOS/pasture-mcp",
            feedFormat: .markdown)
        #expect(command.contains("PASTURE_FEED_FORMAT=markdown"))
    }

    @Test func claudeCodeCommandQuotesPathWithSpaces() {
        let command = MCPConfigGenerator.claudeCodeCommand(
            binaryPath: "/Users/me/My Apps/Pasture.app/Contents/MacOS/pasture-mcp",
            feedFormat: .xml)
        #expect(command.contains("\"/Users/me/My Apps/Pasture.app/Contents/MacOS/pasture-mcp\""))
    }

    // MARK: — Claude Desktop (claude_desktop_config.json)

    @Test func claudeDesktopJSONIsValidAndParseable() throws {
        let json = MCPConfigGenerator.claudeDesktopJSON(
            binaryPath: "/Applications/Pasture.app/Contents/MacOS/pasture-mcp",
            feedFormat: .xml)
        // Debe parsear como JSON válido.
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let pasture = value.object?["mcpServers"]?.object?["pasture"]?.object
        #expect(pasture?["command"]?.stringValue == "/Applications/Pasture.app/Contents/MacOS/pasture-mcp")
    }

    @Test func claudeDesktopJSONInjectsFeedFormatEnv() throws {
        let json = MCPConfigGenerator.claudeDesktopJSON(
            binaryPath: "/Applications/Pasture.app/Contents/MacOS/pasture-mcp",
            feedFormat: .plainText)
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let env = value.object?["mcpServers"]?.object?["pasture"]?.object?["env"]?.object
        #expect(env?["PASTURE_FEED_FORMAT"]?.stringValue == "plainText")
    }

    @Test func claudeDesktopJSONEscapesPathWithSpecialChars() throws {
        // Una ruta con comillas/backslashes debe escaparse vía JSONEncoder, no
        // concatenación. El JSON resultante sigue siendo parseable.
        let weirdPath = #"/Users/me/Quote"Path/pasture-mcp"#
        let json = MCPConfigGenerator.claudeDesktopJSON(binaryPath: weirdPath, feedFormat: .xml)
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let command = value.object?["mcpServers"]?.object?["pasture"]?.object?["command"]?.stringValue
        #expect(command == weirdPath)
    }
}
