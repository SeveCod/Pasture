import Foundation
import Testing
@testable import PastureKit

@Suite("HeadlessFeed")
struct HeadlessFeedTests {

    private func makeVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadlessFeedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePreset(paths: [String]) -> SelectionPreset {
        SelectionPreset(name: "test", relativePaths: paths)
    }

    @Test func successWithPartialMissing() throws {
        let vault = try makeVault()
        try "# uno".write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# dos".write(to: vault.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let preset = makePreset(paths: ["a.md", "b.md", "gone.md"])

        let outcome = HeadlessFeed.build(preset: preset, base: vault, format: .xml)
        guard case .success(let result) = outcome else {
            Issue.record("Expected .success, got \(outcome)")
            return
        }
        #expect(result.fileCount == 2)
        #expect(result.missingPaths == ["gone.md"])
        // ContextBuilder añade ".md" al nombre: pasarle "a.md" produciría "a.md.md".
        #expect(result.context.contains("name=\"a.md\""))
        #expect(!result.context.contains("a.md.md"))
        #expect(result.tokens > 0)
    }

    @Test func allMissingReturnsNoFiles() throws {
        let vault = try makeVault()
        let preset = makePreset(paths: ["x.md", "../escape.md"])
        let outcome = HeadlessFeed.build(preset: preset, base: vault, format: .xml)
        guard case .noFiles(let missing) = outcome else {
            Issue.record("Expected .noFiles, got \(outcome)")
            return
        }
        #expect(missing.count == 2)
    }

    @Test func secretsBlockTheFeed() throws {
        let vault = try makeVault()
        // Literal concatenado: GitHub Push Protection bloquea fixtures realistas.
        let fakeKey = "sk-ant-" + String(repeating: "a", count: 24)
        try "clave: \(fakeKey)".write(to: vault.appendingPathComponent("leak.md"), atomically: true, encoding: .utf8)
        let preset = makePreset(paths: ["leak.md"])

        let outcome = HeadlessFeed.build(preset: preset, base: vault, format: .xml)
        guard case .secretsDetected(let lines) = outcome else {
            Issue.record("Expected .secretsDetected, got \(outcome)")
            return
        }
        #expect(!lines.isEmpty)
        #expect(!lines.joined().contains(fakeKey))  // SEC-4: nunca el valor
    }
}
