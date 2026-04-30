import Testing
@testable import PastureKit
import Foundation

@Suite struct PathValidatorTests {

    private let base = URL(fileURLWithPath: "/Users/test/.pasture")

    // MARK: - Valid paths

    @Test func fileDirectlyInsideBase() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/file.md")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func fileInSubdirectory() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/collection/file.md")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func fileInDeepSubdirectory() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/a/b/c/file.md")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func targetEqualsBase() {
        #expect(PathValidator.isInside(target: base, base: base))
    }

    // MARK: - Path traversal attacks

    @Test func dotDotTraversalRejected() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/../.ssh/id_rsa")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    @Test func dotDotAfterSubdirRejected() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/collection/../../etc/passwd")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    @Test func multipleDotDotRejected() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/../../../etc/shadow")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    // MARK: - Prefix tricks

    @Test func similarPrefixNotMatched() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture-evil/file.md")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    @Test func prefixWithExtraSuffixNotMatched() {
        let target = URL(fileURLWithPath: "/Users/test/.pasturefiles/file.md")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    // MARK: - Completely different paths

    @Test func entirelyDifferentPathRejected() {
        let target = URL(fileURLWithPath: "/tmp/evil.md")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    @Test func parentDirectoryRejected() {
        let target = URL(fileURLWithPath: "/Users/test")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    @Test func rootRejected() {
        let target = URL(fileURLWithPath: "/")
        #expect(!PathValidator.isInside(target: target, base: base))
    }

    // MARK: - Normalization

    @Test func trailingSlashNormalized() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/file.md/")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func dotSegmentNormalized() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/./file.md")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func baseWithTrailingSlash() {
        let baseSlash = URL(fileURLWithPath: "/Users/test/.pasture/")
        let target = URL(fileURLWithPath: "/Users/test/.pasture/file.md")
        #expect(PathValidator.isInside(target: target, base: baseSlash))
    }

    // MARK: - Edge cases

    @Test func emptyFilename() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func specialCharactersInPath() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/file with spaces.md")
        #expect(PathValidator.isInside(target: target, base: base))
    }

    @Test func unicodeInPath() {
        let target = URL(fileURLWithPath: "/Users/test/.pasture/ñoño.md")
        #expect(PathValidator.isInside(target: target, base: base))
    }
}
