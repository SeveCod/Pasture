import Testing
@testable import PastureKit
import Foundation

@Suite struct MDFileTests {

    private let base = URL(fileURLWithPath: "/Users/test/.pasture")

    private func makeFile(
        name: String = "test",
        path: String = "/Users/test/.pasture/test.md",
        content: String = "Hello",
        tokens: Int = 1,
        hasTemplateVars: Bool = false
    ) -> MDFile {
        MDFile(
            name: name,
            url: URL(fileURLWithPath: path),
            modifiedDate: Date(),
            content: content,
            tokens: tokens,
            hasTemplateVars: hasTemplateVars
        )
    }

    // MARK: - Memberwise init

    @Test func memberwiseInitSetsAllFields() {
        let date = Date(timeIntervalSince1970: 1000)
        let file = MDFile(
            name: "notes",
            url: URL(fileURLWithPath: "/tmp/notes.md"),
            modifiedDate: date,
            content: "# Hello",
            tokens: 42,
            hasTemplateVars: true
        )
        #expect(file.name == "notes")
        #expect(file.url == URL(fileURLWithPath: "/tmp/notes.md"))
        #expect(file.modifiedDate == date)
        #expect(file.content == "# Hello")
        #expect(file.tokens == 42)
        #expect(file.hasTemplateVars == true)
    }

    @Test func idIsURL() {
        let file = makeFile(path: "/tmp/file.md")
        #expect(file.id == URL(fileURLWithPath: "/tmp/file.md"))
    }

    // MARK: - Collection

    @Test func fileInBaseHasNoCollection() {
        let file = makeFile(path: "/Users/test/.pasture/file.md")
        #expect(file.collection(relativeTo: base) == nil)
    }

    @Test func fileInSubdirectoryReturnsCollectionName() {
        let file = makeFile(path: "/Users/test/.pasture/work/file.md")
        #expect(file.collection(relativeTo: base) == "work")
    }

    @Test func fileOutsideBaseReturnsNil() {
        let file = makeFile(path: "/tmp/file.md")
        #expect(file.collection(relativeTo: base) == nil)
    }

    @Test func fileInNestedSubdirReturnsImmediateParent() {
        let file = makeFile(path: "/Users/test/.pasture/a/b/file.md")
        #expect(file.collection(relativeTo: base) == "b")
    }

    @Test func collectionWithDotDotReturnsNil() {
        let file = makeFile(path: "/Users/test/.pasture/../.ssh/file.md")
        #expect(file.collection(relativeTo: base) == nil)
    }

    // MARK: - Equality & hashing

    @Test func equalityByURL() {
        let a = MDFile(name: "a", url: URL(fileURLWithPath: "/tmp/x.md"), modifiedDate: Date(), content: "aaa", tokens: 1, hasTemplateVars: false)
        let b = MDFile(name: "b", url: URL(fileURLWithPath: "/tmp/x.md"), modifiedDate: Date(), content: "bbb", tokens: 2, hasTemplateVars: true)
        #expect(a == b)
    }

    @Test func inequalityByURL() {
        let a = makeFile(path: "/tmp/a.md")
        let b = makeFile(path: "/tmp/b.md")
        #expect(a != b)
    }

    @Test func hashConsistentWithEquality() {
        let a = MDFile(name: "a", url: URL(fileURLWithPath: "/tmp/x.md"), modifiedDate: Date(), content: "aaa", tokens: 1, hasTemplateVars: false)
        let b = MDFile(name: "b", url: URL(fileURLWithPath: "/tmp/x.md"), modifiedDate: Date(), content: "bbb", tokens: 2, hasTemplateVars: true)
        #expect(a.hashValue == b.hashValue)
    }

    @Test func differentURLsDifferentHash() {
        let a = makeFile(path: "/tmp/a.md")
        let b = makeFile(path: "/tmp/b.md")
        #expect(a.hashValue != b.hashValue)
    }

    // MARK: - updateDerivedProperties

    @Test func updateDerivedPropertiesRecalculates() {
        var file = MDFile(name: "test", url: URL(fileURLWithPath: "/tmp/test.md"), modifiedDate: Date(), content: "short", tokens: 0, hasTemplateVars: false)
        file.content = String(repeating: "word ", count: 100)
        file.updateDerivedProperties()
        #expect(file.tokens > 0)
        #expect(file.tokens == TokenEstimator.estimate(file.content))
    }

    @Test func updateDerivedPropertiesDetectsTemplateVars() {
        var file = makeFile(content: "no vars here")
        #expect(file.hasTemplateVars == false)
        file.content = "Hello {{NAME}}"
        file.updateDerivedProperties()
        #expect(file.hasTemplateVars == true)
    }

    // MARK: - I/O init

    @Test func ioInitWithNonexistentFile() {
        let file = MDFile(url: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).md"))
        #expect(file.content.isEmpty)
        #expect(file.tokens == 0)
    }

    @Test func ioInitExtractsNameFromURL() {
        let file = MDFile(url: URL(fileURLWithPath: "/tmp/my-notes.md"))
        #expect(file.name == "my-notes")
    }

    @Test func ioInitWithRealFile() throws {
        let tmpURL = URL(fileURLWithPath: "/tmp/pasture-test-\(UUID()).md")
        try "# Test content".write(to: tmpURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let file = MDFile(url: tmpURL)
        #expect(file.content == "# Test content")
        #expect(file.name == tmpURL.deletingPathExtension().lastPathComponent)
        #expect(file.tokens > 0)
    }
}
