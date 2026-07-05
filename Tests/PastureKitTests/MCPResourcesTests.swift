import Testing
import Foundation
@testable import PastureKit

/// Primitiva MCP `resources` (v1.6): cada `.md` del vault como resource nativo.
/// Todo se ejercita a través de `MCPDispatcher.handle(line:)` (sin spawn) más
/// tests unitarios del parser de uri. Invariantes: solo lectura (SEC-M11),
/// traversal (SEC-M1), symlink (SEC-M2), cap de tamaño (SEC-M5).
@Suite struct MCPResourcesTests {

    // MARK: — Fixture

    private func makeVault() -> (MCPDispatcher, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-resources-\(UUID().uuidString)", isDirectory: true)
        let collection = root.appendingPathComponent("proyecto", isDirectory: true)
        try? FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        try? "Notas raíz.".write(to: root.appendingPathComponent("notas.md"), atomically: true, encoding: .utf8)
        try? "# Spec".write(to: collection.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))
        return (dispatcher, root)
    }

    private func decode(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    // MARK: — uri ⇄ ruta relativa (unitario)

    @Test func uriRoundTripsForRootFile() {
        #expect(MCPResources.uri(forRelativePath: "notas.md") == "pasture:///notas.md")
        #expect(MCPResources.relativePath(fromURI: "pasture:///notas.md") == "notas.md")
    }

    @Test func uriRoundTripsForCollectionFile() {
        #expect(MCPResources.uri(forRelativePath: "proyecto/spec.md") == "pasture:///proyecto/spec.md")
        #expect(MCPResources.relativePath(fromURI: "pasture:///proyecto/spec.md") == "proyecto/spec.md")
    }

    @Test func relativePathRejectsForeignScheme() {
        #expect(MCPResources.relativePath(fromURI: "file:///etc/passwd") == nil)
        #expect(MCPResources.relativePath(fromURI: "https://example.com/a.md") == nil)
    }

    // MARK: — AC#2: resources/list

    @Test func listReturnsExactlyTheVaultFiles() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"resources/list"}"#))
        let json = try decode(line)
        let resources = try #require(json.object?["result"]?.object?["resources"]?.arrayValue)
        #expect(resources.count == 2)

        let uris = Set(resources.compactMap { $0.object?["uri"]?.stringValue })
        #expect(uris == ["pasture:///notas.md", "pasture:///proyecto/spec.md"])

        // name = ruta relativa, mimeType = text/markdown en todos.
        for resource in resources {
            let obj = resource.object
            #expect(obj?["mimeType"]?.stringValue == "text/markdown")
            let name = obj?["name"]?.stringValue
            #expect(name == "notas.md" || name == "proyecto/spec.md")
        }
    }

    /// Framing (ADR-006): una línea, sin `\/` escapado en los uri (llevan barras).
    @Test func listResponseIsOneLineWithUnescapedSlashes() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"resources/list"}"#))
        #expect(!line.contains("\n"))
        #expect(!line.contains(#"\/"#))
        #expect(line.contains("pasture:///proyecto/spec.md"))
    }

    // MARK: — AC#2 (read feliz)

    @Test func readReturnsContentsForValidURI() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"pasture:///notas.md"}}"#))
        let json = try decode(line)
        let contents = try #require(json.object?["result"]?.object?["contents"]?.arrayValue)
        #expect(contents.count == 1)
        #expect(contents.first?.object?["text"]?.stringValue == "Notas raíz.")
        #expect(contents.first?.object?["uri"]?.stringValue == "pasture:///notas.md")
        #expect(contents.first?.object?["mimeType"]?.stringValue == "text/markdown")
    }

    // MARK: — AC#3: symlink fuera del vault

    @Test func symlinkIsNotListedAndReadIsRejected() throws {
        let (dispatcher, root) = makeVault()
        let link = root.appendingPathComponent("evil.md")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))

        // Parte 1: no aparece en la lista (FileLibrary filtra symlinks).
        let listLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"resources/list"}"#))
        let uris = try decode(listLine).object?["result"]?.object?["resources"]?.arrayValue?
            .compactMap { $0.object?["uri"]?.stringValue } ?? []
        #expect(!uris.contains("pasture:///evil.md"))

        // Parte 2: read por su uri → error de protocolo, sin leer /etc/passwd.
        let readLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"pasture:///evil.md"}}"#))
        let json = try decode(readLine)
        #expect(json.object?["error"]?.object?["code"]?.stringValue == nil)  // hay 'error'
        #expect(json.object?["error"] != nil)
        #expect(json.object?["result"] == nil)
        let msg = json.object?["error"]?.object?["message"]?.stringValue ?? ""
        #expect(msg.contains("fuera del vault"))
    }

    // MARK: — AC#4: traversal y esquema ajeno

    @Test func readRejectsTraversalURI() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{"uri":"pasture:///../../.ssh/id_rsa"}}"#))
        let json = try decode(line)
        #expect(json.object?["error"] != nil)
        #expect(json.object?["result"] == nil)
    }

    @Test func readRejectsForeignScheme() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"file:///etc/passwd"}}"#))
        let json = try decode(line)
        let error = try #require(json.object?["error"]?.object)
        #expect(error["code"] != nil)
        #expect(json.object?["result"] == nil)
    }

    @Test func readRejectsMissingURI() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":7,"method":"resources/read","params":{}}"#))
        let json = try decode(line)
        #expect(json.object?["error"] != nil)
    }

    // MARK: — AC#5: cap de tamaño (25 MB) sin materializar

    @Test func readRejectsOversizedFileBySizeOnDisk() throws {
        let (dispatcher, root) = makeVault()
        let big = root.appendingPathComponent("big.md")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(MCPLimits.maxResponseBytes) + 1)
        try handle.close()

        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":8,"method":"resources/read","params":{"uri":"pasture:///big.md"}}"#))
        let json = try decode(line)
        #expect(json.object?["error"] != nil)
        let msg = json.object?["error"]?.object?["message"]?.stringValue ?? ""
        #expect(msg.contains("demasiado grande"))
    }

    // MARK: — Vault vacío

    @Test func listOnEmptyVaultReturnsEmptyArray() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-empty-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":9,"method":"resources/list"}"#))
        let json = try decode(line)
        #expect(json.object?["result"]?.object?["resources"]?.arrayValue?.isEmpty == true)
    }
}
