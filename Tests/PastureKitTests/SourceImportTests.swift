import Testing
import Foundation
@testable import PastureKit

/// Memoria viva (v1.7, Fase B) — validación de fuentes + decisión de re-importación.
@Suite struct SourceImportTests {

    private func makeVault() throws -> URL {
        let base = try makeTempDirectory()
        let vault = base.appendingPathComponent(".pasture", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    // MARK: — SourceValidator (AC#12)

    @Test func acceptsExistingLocalDirectoryOutsideVault() throws {
        let vault = try makeVault()
        let docs = vault.deletingLastPathComponent().appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        guard case .success = SourceValidator.validate(sourcePath: docs.path, vaultRoot: vault) else {
            Issue.record("una carpeta local fuera del vault debe aceptarse"); return
        }
    }

    @Test func rejectsNonexistentPath() throws {
        let vault = try makeVault()
        #expect(SourceValidator.validate(sourcePath: "/no/existe/xyz", vaultRoot: vault) == .failure(.notFound))
    }

    @Test func rejectsFileInsteadOfDirectory() throws {
        let vault = try makeVault()
        let file = vault.deletingLastPathComponent().appendingPathComponent("f.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(SourceValidator.validate(sourcePath: file.path, vaultRoot: vault) == .failure(.notADirectory))
    }

    @Test func rejectsFolderInsideVault() throws {
        let vault = try makeVault()
        let inside = vault.appendingPathComponent("coleccion", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        #expect(SourceValidator.validate(sourcePath: inside.path, vaultRoot: vault) == .failure(.insideVault))
    }

    @Test func rejectsSymlinkResolvingIntoVault() throws {
        let vault = try makeVault()
        let insideDir = vault.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: insideDir, withIntermediateDirectories: true)
        let link = vault.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: insideDir)
        #expect(SourceValidator.validate(sourcePath: link.path, vaultRoot: vault) == .failure(.insideVault))
    }

    @Test func rejectsEmptySource() throws {
        let vault = try makeVault()
        #expect(SourceValidator.validate(sourcePath: "   ", vaultRoot: vault) == .failure(.empty))
    }

    // MARK: — SourceImportDecision (AC#11)

    @Test func decisionCreateWhenAbsent() {
        #expect(SourceImportDecision.decide(existingContent: nil) == .create)
    }

    @Test func decisionOverwriteWhenGenerated() {
        #expect(SourceImportDecision.decide(existingContent: "---\ngenerated: true\n---\nx") == .overwrite)
    }

    @Test func decisionSkipWhenGeneratedRemoved() {
        // El usuario editó la nota y quitó `generated` → desvinculada, protegida.
        #expect(SourceImportDecision.decide(existingContent: "---\nttl: 90\n---\neditado a mano") == .skipUnlinked)
    }

    @Test func decisionSkipWhenHandAuthored() {
        #expect(SourceImportDecision.decide(existingContent: "# Nota a mano\nsin frontmatter") == .skipUnlinked)
    }

    // MARK: — FrontmatterWriter.markingGenerated

    @Test func markingGeneratedInjectsFlag() {
        let result = FrontmatterWriter.markingGenerated(in: "cuerpo puro")
        let fm = try! #require(FrontmatterParser.parse(result).frontmatter)
        #expect(fm.generated)
        #expect(FrontmatterParser.parse(result).body == "cuerpo puro")
    }

    @Test func markingGeneratedPreservesExistingKeys() {
        let result = FrontmatterWriter.markingGenerated(in: "---\nttl: 30\n---\nc")
        let fm = try! #require(FrontmatterParser.parse(result).frontmatter)
        #expect(fm.generated)
        #expect(fm.ttlDays == 30)
    }
}
