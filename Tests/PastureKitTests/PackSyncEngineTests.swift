import Testing
import Foundation
@testable import PastureKit

/// Context Compiler (v1.6) — orquestación end-to-end preset → compile → write.
@Suite struct PackSyncEngineTests {

    private struct Fixture {
        let vault: URL
        let repo: URL
        let backups: URL
    }

    private func makeFixture(files: [String: String]) throws -> Fixture {
        let base = try makeTempDirectory()
        let vault = base.appendingPathComponent(".pasture", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        for (rel, content) in files {
            let url = vault.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        let repo = base.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        return Fixture(vault: vault, repo: repo, backups: base.appendingPathComponent("backups", isDirectory: true))
    }

    // MARK: — AC#1 end-to-end: preset con variable → destino compilado

    @Test func compilesAndWritesTargetEndToEnd() throws {
        let f = try makeFixture(files: ["rules.md": "Reglas de {{PROJECT}}"])
        let preset = SelectionPreset(name: "sel", relativePaths: ["rules.md"])
        let target = CompileTarget(kind: .claudeMd, absolutePath: f.repo.appendingPathComponent("CLAUDE.md").path)
        let pack = CompilePack(name: "mi-pack", presetID: preset.id, variables: ["PROJECT": "foo"], targets: [target])
        let ctx = PackSyncEngine.Context(vaultRoot: f.vault, backupsRoot: f.backups)

        guard case .success(let results) = PackSyncEngine.sync(pack: pack, preset: preset, context: ctx) else {
            Issue.record("esperaba éxito"); return
        }
        #expect(results.count == 1)
        guard case .written = results[0].outcome else { Issue.record("esperaba .written"); return }

        let written = try #require(try? String(contentsOf: f.repo.appendingPathComponent("CLAUDE.md"), encoding: .utf8))
        let parsed = try #require(SyncMarker.parse(written))
        #expect(parsed.body == "## rules.md\n```\nReglas de foo\n```")
    }

    // MARK: — AC#5: faltan ficheros fuente → aborta sin emitir

    @Test func abortsWhenSourceFilesMissing() throws {
        let f = try makeFixture(files: ["exists.md": "ok"])
        // El preset referencia un fichero borrado + una ruta con traversal.
        let preset = SelectionPreset(name: "sel", relativePaths: ["exists.md", "gone.md", "../../etc/passwd"])
        let target = CompileTarget(kind: .claudeMd, absolutePath: f.repo.appendingPathComponent("CLAUDE.md").path)
        let pack = CompilePack(name: "p", presetID: preset.id, targets: [target])
        let ctx = PackSyncEngine.Context(vaultRoot: f.vault, backupsRoot: f.backups)

        guard case .failure(let error) = PackSyncEngine.sync(pack: pack, preset: preset, context: ctx) else {
            Issue.record("esperaba abortar por ficheros ausentes"); return
        }
        guard case .missingSourceFiles(let missing) = error else { Issue.record("tipo de error"); return }
        #expect(missing.contains("gone.md"))
        #expect(missing.contains("../../etc/passwd"))
        // No se escribió el destino.
        #expect(!FileManager.default.fileExists(atPath: f.repo.appendingPathComponent("CLAUDE.md").path))
    }

    // MARK: — preset ausente

    @Test func failsWhenPresetMissing() throws {
        let f = try makeFixture(files: [:])
        let pack = CompilePack(name: "p", presetID: UUID(), targets: [])
        let ctx = PackSyncEngine.Context(vaultRoot: f.vault, backupsRoot: f.backups)
        #expect(PackSyncEngine.sync(pack: pack, preset: nil, context: ctx) == .failure(.presetMissing))
    }

    // MARK: — AC#4 vía engine: destino dentro del vault → failed, no escribe

    @Test func targetInsideVaultFailsWithoutWriting() throws {
        let f = try makeFixture(files: ["a.md": "x"])
        let preset = SelectionPreset(name: "sel", relativePaths: ["a.md"])
        // Destino DENTRO del vault (prohibido).
        let target = CompileTarget(kind: .claudeMd, absolutePath: f.vault.appendingPathComponent("CLAUDE.md").path)
        let pack = CompilePack(name: "p", presetID: preset.id, targets: [target])
        let ctx = PackSyncEngine.Context(vaultRoot: f.vault, backupsRoot: f.backups)

        guard case .success(let results) = PackSyncEngine.sync(pack: pack, preset: preset, context: ctx) else {
            Issue.record("esperaba success con outcome failed"); return
        }
        guard case .failed = results[0].outcome else { Issue.record("esperaba .failed"); return }
        #expect(!FileManager.default.fileExists(atPath: f.vault.appendingPathComponent("CLAUDE.md").path))
    }
}
