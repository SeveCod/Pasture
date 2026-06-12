import Testing
@testable import PastureKit
import Foundation

@Suite struct FileLibraryTests {

    private func write(_ content: String, to dir: URL, name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - deduplicatedURL

    @Test func deduplicatedURLReturnsBaseWhenFree() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = FileLibrary.deduplicatedURL(baseName: "notes", ext: "md", in: dir)
        #expect(url.lastPathComponent == "notes.md")
    }

    @Test func deduplicatedURLAppendsCounterOnCollision() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("a", to: dir, name: "notes.md")
        _ = try write("b", to: dir, name: "notes-2.md")

        let url = FileLibrary.deduplicatedURL(baseName: "notes", ext: "md", in: dir)
        #expect(url.lastPathComponent == "notes-3.md")
    }

    @Test func deduplicatedURLHandlesEmptyExtension() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("a", to: dir, name: "notes")

        let url = FileLibrary.deduplicatedURL(baseName: "notes", ext: "", in: dir)
        #expect(url.lastPathComponent == "notes-2")
    }

    // MARK: - mdFiles

    @Test func mdFilesIgnoresNonMarkdownAndHidden() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("# A", to: dir, name: "a.md")
        _ = try write("text", to: dir, name: "b.txt")
        _ = try write("hidden", to: dir, name: ".hidden.md")

        let files = FileLibrary.mdFiles(in: dir)
        #expect(files.map(\.name) == ["a"])
    }

    @Test func mdFilesExcludesSymlinks() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = try write("# A", to: dir, name: "real.md")
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("link.md"),
            withDestinationURL: real
        )

        let files = FileLibrary.mdFiles(in: dir)
        #expect(files.map(\.name) == ["real"])
    }

    // MARK: - realSubdirectories

    @Test func realSubdirectoriesIgnoresFilesAndHiddenDirs() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("visible"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".hiddenDir"), withIntermediateDirectories: false)
        _ = try write("x", to: dir, name: "file.md")

        let subdirs = FileLibrary.realSubdirectories(in: dir)
        #expect(subdirs.map(\.lastPathComponent) == ["visible"])
    }

    // MARK: - visibleContents (regression: .DS_Store must not block collection deletion)

    @Test func visibleContentsSkipsHiddenFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("junk", to: dir, name: ".DS_Store")

        let contents = try FileLibrary.visibleContents(of: dir)
        #expect(contents.isEmpty)
    }

    @Test func visibleContentsListsVisibleFiles() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try write("junk", to: dir, name: ".DS_Store")
        _ = try write("# A", to: dir, name: "a.md")

        let contents = try FileLibrary.visibleContents(of: dir)
        #expect(contents.map(\.lastPathComponent) == ["a.md"])
    }

    @Test func visibleContentsThrowsForMissingDirectory() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        #expect(throws: (any Error).self) {
            try FileLibrary.visibleContents(of: missing)
        }
    }

    // MARK: - load

    @Test func loadCollectsRootAndSubdirectoryFilesSortedByDate() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let subdir = dir.appendingPathComponent("collection")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: false)

        let older = try write("# Old", to: dir, name: "old.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1000)],
            ofItemAtPath: older.path
        )
        let newer = try write("# New", to: subdir, name: "new.md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2000)],
            ofItemAtPath: newer.path
        )

        let result = await FileLibrary.load(at: dir)
        #expect(result.files.map(\.name) == ["new", "old"])
        #expect(result.subdirectories.map(\.lastPathComponent) == ["collection"])
    }

    @Test func loadReturnsEmptyForMissingDirectory() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        let result = await FileLibrary.load(at: missing)
        #expect(result.files.isEmpty)
        #expect(result.subdirectories.isEmpty)
    }
}
