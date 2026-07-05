import Testing
import Foundation
@testable import PastureKit

/// Context Compiler (v1.6) — el vault jamás puede ser destino de escritura (AC#4).
@Suite struct TargetValidatorTests {

    private func makeVault() throws -> URL {
        let base = try makeTempDirectory()
        let vault = base.appendingPathComponent(".pasture", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    @Test func acceptsTargetOutsideVault() throws {
        let vault = try makeVault()
        let target = vault.deletingLastPathComponent().appendingPathComponent("repo/CLAUDE.md").path
        guard case .success(let url) = TargetValidator.validate(targetPath: target, vaultRoot: vault) else {
            Issue.record("un destino fuera del vault debe aceptarse")
            return
        }
        #expect(url.path == target)
    }

    @Test func rejectsTargetDirectlyInsideVault() throws {
        let vault = try makeVault()
        let target = vault.appendingPathComponent("CLAUDE.md").path
        #expect(TargetValidator.validate(targetPath: target, vaultRoot: vault) == .failure(.insideVault))
    }

    @Test func rejectsTargetInsideVaultViaDotDot() throws {
        let vault = try makeVault()
        // /…/.pasture/sub/../secret.md → /…/.pasture/secret.md (dentro del vault).
        let target = vault.appendingPathComponent("sub/../secret.md").path
        #expect(TargetValidator.validate(targetPath: target, vaultRoot: vault) == .failure(.insideVault))
    }

    @Test func rejectsSymlinkPointingIntoVault() throws {
        let vault = try makeVault()
        let outside = vault.deletingLastPathComponent()
        // symlink 'link.md' fuera del vault que apunta a un fichero DENTRO del vault.
        let link = outside.appendingPathComponent("link.md")
        let insideTarget = vault.appendingPathComponent("real.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: insideTarget)
        #expect(TargetValidator.validate(targetPath: link.path, vaultRoot: vault) == .failure(.insideVault))
    }

    @Test func rejectsRelativePath() throws {
        let vault = try makeVault()
        #expect(TargetValidator.validate(targetPath: "relative/CLAUDE.md", vaultRoot: vault) == .failure(.notAbsolute))
    }
}
