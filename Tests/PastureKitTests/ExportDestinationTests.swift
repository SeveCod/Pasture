import Testing
import Foundation
@testable import PastureKit

@Suite("ExportDestination")
struct ExportDestinationTests {

    @Test("URL is constructed from path")
    func urlFromPath() {
        let dest = ExportDestination(name: "Test", path: "/tmp/context.md")
        #expect(dest.url == URL(fileURLWithPath: "/tmp/context.md"))
    }

    @Test("isWritable returns true for writable directory")
    func writableDirectory() {
        let dest = ExportDestination(name: "Tmp", path: "/tmp/test-context.md")
        #expect(dest.isWritable)
    }

    @Test("isWritable returns false for nonexistent directory")
    func nonexistentDirectory() {
        let dest = ExportDestination(name: "Bad", path: "/nonexistent-dir-xyz/context.md")
        #expect(!dest.isWritable)
    }

    @Test("Codable roundtrip preserves data")
    func codableRoundtrip() throws {
        let original = ExportDestination(name: "MyProject", path: "/Users/test/project/CONTEXT.md")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExportDestination.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.path == original.path)
    }

    @Test("Hashable works for Set usage")
    func hashable() {
        let a = ExportDestination(name: "A", path: "/a")
        let b = ExportDestination(name: "B", path: "/b")
        let set: Set<ExportDestination> = [a, b, a]
        #expect(set.count == 2)
    }
}
