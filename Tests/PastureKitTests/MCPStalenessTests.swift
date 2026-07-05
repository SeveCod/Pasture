import Testing
import Foundation
@testable import PastureKit

/// Memoria viva (v1.7, Fase A) — anotación de staleness por el canal `warning`
/// del MCP (SEC-M8), sin alterar contenido ni romper el read-only (SEC-M11).
/// Se usa `review_after` en el pasado lejano para que la caducidad sea
/// independiente del reloj real.
@Suite struct MCPStalenessTests {

    private func makeVault() -> (MCPDispatcher, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-stale-\(UUID().uuidString)", isDirectory: true)
        let collection = root.appendingPathComponent("notas", isDirectory: true)
        try? FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        // Nota caducada (review_after en el pasado) y nota fresca.
        try? "---\nreview_after: 2000-01-01\n---\ncontenido viejo"
            .write(to: collection.appendingPathComponent("vieja.md"), atomically: true, encoding: .utf8)
        try? "---\nreview_after: 2999-01-01\n---\ncontenido fresco"
            .write(to: collection.appendingPathComponent("fresca.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))
        return (dispatcher, root)
    }

    private func decode(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    // MARK: — Helper puro

    @Test func stalenessWarningPureHelper() {
        let expired = "---\nreview_after: 2000-01-01\n---\nx"
        let fresh = "---\nreview_after: 2999-01-01\n---\nx"
        #expect(MCPTools.stalenessWarning(content: expired, reference: Date(), now: Date())?.contains("stale") == true)
        #expect(MCPTools.stalenessWarning(content: fresh, reference: Date(), now: Date()) == nil)
        #expect(MCPTools.stalenessWarning(content: "sin frontmatter", reference: Date(), now: Date()) == nil)
    }

    // MARK: — AC#7: read_file anota staleness en warning, contenido íntegro

    @Test func readFileWarnsWhenStale() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"notas/vieja.md"}}}"#))
        let result = try #require(try decode(line).object?["result"]?.object)
        #expect(result["isError"] != nil)
        let warning = result["warning"]?.stringValue ?? ""
        #expect(warning.contains("stale"))
        #expect(warning.contains("since last review"))
        // Contenido entregado íntegro (incluye el frontmatter en v1).
        let content = result["content"]?.arrayValue?.first?.object?["text"]?.stringValue ?? ""
        #expect(content.contains("contenido viejo"))
    }

    @Test func readFileFreshHasNoStaleWarning() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"notas/fresca.md"}}}"#))
        let result = try #require(try decode(line).object?["result"]?.object)
        let warning = result["warning"]?.stringValue ?? ""
        #expect(!warning.contains("stale"))
    }

    // MARK: — AC#8: feed_context lista solo las vencidas

    @Test func feedContextListsOnlyStaleFiles() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"feed_context","arguments":{"collection":"notas"}}}"#))
        let result = try #require(try decode(line).object?["result"]?.object)
        let warning = result["warning"]?.stringValue ?? ""
        #expect(warning.contains("stale since last review"))
        #expect(warning.contains("vieja.md"))
        #expect(!warning.contains("fresca.md"))
    }

    // MARK: — AC#9: secreto + staleness coexisten en el warning

    @Test func readFileCombinesSecretAndStaleWarnings() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-stale2-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = "sk-ant-" + "api03-" + "abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        try? "---\nreview_after: 2000-01-01\n---\nclave \(key)"
            .write(to: root.appendingPathComponent("leak.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))

        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"leak.md"}}}"#))
        let warning = try #require(try decode(line).object?["result"]?.object?["warning"]?.stringValue)
        #expect(warning.contains("stale"))
        #expect(warning.contains("secrets") || warning.contains("Anthropic"))
        #expect(!warning.contains(key))   // nunca el valor
    }
}
