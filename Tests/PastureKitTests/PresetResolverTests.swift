import Testing
import Foundation
@testable import PastureKit

/// F2 — Resolución pura de rutas de preset.
/// SEC-9: toda ruta se valida contra `~/.pasture/` vía PathValidator; una ruta
/// que escape (`../`) se descarta y cuenta como ausente.
@Suite("PresetResolver")
struct PresetResolverTests {

    private let base = URL(fileURLWithPath: "/Users/test/.pasture", isDirectory: true)

    @Test("Resolves relative path to absolute URL inside base")
    func resolvesInside() {
        let result = PresetResolver.resolve(relativePaths: ["notes.md"], base: base)
        #expect(result.urls == [base.appendingPathComponent("notes.md")])
        #expect(result.rejectedCount == 0)
    }

    @Test("Resolves nested path inside a collection")
    func resolvesNested() {
        let result = PresetResolver.resolve(relativePaths: ["projectX/spec.md"], base: base)
        #expect(result.urls == [base.appendingPathComponent("projectX/spec.md")])
        #expect(result.rejectedCount == 0)
    }

    // SEC-9: path traversal se descarta.
    @Test("Rejects path traversal (../) — SEC-9")
    func rejectsTraversal() {
        let result = PresetResolver.resolve(relativePaths: ["../../etc/passwd"], base: base)
        #expect(result.urls.isEmpty)
        #expect(result.rejectedCount == 1)
    }

    @Test("Rejects absolute-looking escape, keeps valid ones, counts rejected")
    func mixedSafeAndUnsafe() {
        let result = PresetResolver.resolve(
            relativePaths: ["a.md", "../escape.md", "sub/b.md"],
            base: base
        )
        #expect(result.urls.count == 2)
        #expect(result.rejectedCount == 1)
        #expect(result.urls.contains(base.appendingPathComponent("a.md")))
        #expect(result.urls.contains(base.appendingPathComponent("sub/b.md")))
    }

    @Test("Empty paths yield empty result")
    func empty() {
        let result = PresetResolver.resolve(relativePaths: [], base: base)
        #expect(result.urls.isEmpty)
        #expect(result.rejectedCount == 0)
    }

    @Test("relativePath strips base prefix")
    func relativePathStripsBase() {
        let url = base.appendingPathComponent("sub/file.md")
        #expect(PresetResolver.relativePath(for: url, base: base) == "sub/file.md")
    }

    @Test("relativePath returns nil for URL outside base")
    func relativePathOutside() {
        let outside = URL(fileURLWithPath: "/tmp/other.md")
        #expect(PresetResolver.relativePath(for: outside, base: base) == nil)
    }

    // MARK: — M-3: paths ausentes (no existen en disco o descartados por SEC-9)

    @Test("missingPaths lists paths whose URL is not in the existing set")
    func missingPathsBasic() {
        let existing: Set<URL> = [base.appendingPathComponent("a.md").standardizedFileURL]
        let result = PresetResolver.resolve(
            relativePaths: ["a.md", "gone.md"],
            base: base
        )
        let missing = PresetResolver.missingPaths(
            relativePaths: ["a.md", "gone.md"],
            base: base,
            existing: existing
        )
        #expect(result.urls.count == 2)   // ambos válidos como ruta
        #expect(missing == ["gone.md"])   // pero solo a.md existe en disco
    }

    @Test("missingPaths counts SEC-9-rejected traversal as missing")
    func missingPathsTraversalCountsAsMissing() {
        let existing: Set<URL> = []
        let missing = PresetResolver.missingPaths(
            relativePaths: ["../escape.md"],
            base: base,
            existing: existing
        )
        #expect(missing == ["../escape.md"])
    }

    @Test("missingPaths empty when all resolve and exist")
    func missingPathsAllPresent() {
        let existing: Set<URL> = [
            base.appendingPathComponent("a.md").standardizedFileURL,
            base.appendingPathComponent("sub/b.md").standardizedFileURL,
        ]
        let missing = PresetResolver.missingPaths(
            relativePaths: ["a.md", "sub/b.md"],
            base: base,
            existing: existing
        )
        #expect(missing.isEmpty)
    }
}
