import Testing
import Foundation
@testable import PastureKit

/// Context Compiler (v1.6) — capa de escritura: conflicto, backup, atomicidad,
/// re-creación y agregación de 'Sync all'. Todo contra directorios temporales.
@Suite struct PackWriterTests {

    private struct Fixture {
        let target: URL
        let backups: URL
    }

    private func makeFixture() throws -> Fixture {
        let base = try makeTempDirectory()
        let repo = base.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let backups = base.appendingPathComponent("backups", isDirectory: true)
        return Fixture(target: repo.appendingPathComponent("CLAUDE.md"), backups: backups)
    }

    private func request(
        _ f: Fixture, body: String, hasSecrets: Bool = false,
        overwrite: Bool = false, secretsAllowed: Bool = false
    ) -> PackWriter.WriteRequest {
        PackWriter.WriteRequest(
            packName: "p", body: body, hasSecrets: hasSecrets, targetURL: f.target,
            backupsRoot: f.backups, overwriteConflict: overwrite, secretsAllowed: secretsAllowed)
    }

    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    // MARK: — AC#1: crear destino con cabecera + cuerpo

    @Test func writesNewTargetWithMarkerHeader() throws {
        let f = try makeFixture()
        let outcome = PackWriter.write(request(f, body: "cuerpo compilado"))
        guard case .written = outcome else { Issue.record("esperaba .written"); return }

        let content = try #require(read(f.target))
        #expect(content.hasPrefix("<!-- pasture-pack: p | sha256:"))
        let parsed = try #require(SyncMarker.parse(content))
        #expect(parsed.body == "cuerpo compilado")
        // El destino recién escrito queda 'clean' (hash coincide).
        #expect(SyncMarker.state(existingFileContent: content) == .clean)
    }

    // MARK: — AC#2: conflicto no se sobrescribe sin confirmación

    @Test func doesNotOverwriteConflictWithoutConfirmation() throws {
        let f = try makeFixture()
        // Un CLAUDE.md preexistente escrito a mano (sin cabecera de Pasture).
        try "# Escrito a mano\nno tocar".write(to: f.target, atomically: true, encoding: .utf8)

        let outcome = PackWriter.write(request(f, body: "nuevo cuerpo de Pasture"))
        #expect(outcome == .conflict)
        #expect(read(f.target) == "# Escrito a mano\nno tocar")   // intacto
    }

    @Test func overwritesConflictWhenConfirmed() throws {
        let f = try makeFixture()
        try "# a mano".write(to: f.target, atomically: true, encoding: .utf8)
        let outcome = PackWriter.write(request(f, body: "cuerpo Pasture", overwrite: true))
        guard case .written = outcome else { Issue.record("esperaba .written"); return }
        #expect(SyncMarker.parse(read(f.target) ?? "")?.body == "cuerpo Pasture")
    }

    // MARK: — AC#3: backup antes de sobrescribir + poda a 10

    @Test func backsUpPreviousContentBeforeOverwrite() throws {
        let f = try makeFixture()
        try "# original a mano".write(to: f.target, atomically: true, encoding: .utf8)
        _ = PackWriter.write(request(f, body: "v1", overwrite: true))

        let subdir = PackWriter.backupSubdir(for: f.target, backupsRoot: f.backups)
        let backups = try FileManager.default.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bak" }
        #expect(backups.count == 1)
        #expect((try? String(contentsOf: backups[0], encoding: .utf8)) == "# original a mano")
        // El backup NO está dentro del repo del usuario ni del vault.
        #expect(!backups[0].path.contains("/repo/"))
    }

    @Test func prunesBackupsToTen() throws {
        let f = try makeFixture()
        // 1ª escritura crea (sin backup); 12 sobrescrituras → 12 backups → poda a 10.
        _ = PackWriter.write(request(f, body: "v0", overwrite: true))
        for i in 1...12 {
            _ = PackWriter.write(request(f, body: "v\(i)", overwrite: true))
        }
        let subdir = PackWriter.backupSubdir(for: f.target, backupsRoot: f.backups)
        let count = (try FileManager.default.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "bak" }.count
        #expect(count == PackWriter.maxBackupsPerTarget)
    }

    // MARK: — AC#10: destino borrado se re-crea sin conflicto

    @Test func recreatesDeletedTargetWithoutConflict() throws {
        let f = try makeFixture()
        _ = PackWriter.write(request(f, body: "v1", overwrite: true))
        try FileManager.default.removeItem(at: f.target)   // el usuario lo borra
        let outcome = PackWriter.write(request(f, body: "v2"))   // sin overwrite
        guard case .written = outcome else { Issue.record("esperaba re-creación"); return }
        #expect(SyncMarker.parse(read(f.target) ?? "")?.body == "v2")
    }

    // MARK: — AC#6: secretos bloquean sin permiso

    @Test func blocksWriteWhenSecretsPresentAndNotAllowed() throws {
        let f = try makeFixture()
        let outcome = PackWriter.write(request(f, body: "clave sk-ant-...", hasSecrets: true))
        #expect(outcome == .secretsBlocked)
        #expect(read(f.target) == nil)   // no se escribió nada
    }

    @Test func writesWithSecretsWhenAllowed() throws {
        let f = try makeFixture()
        let outcome = PackWriter.write(request(f, body: "clave", hasSecrets: true, secretsAllowed: true))
        guard case .written = outcome else { Issue.record("esperaba .written"); return }
    }

    // MARK: — AC#8: agregación de 'Sync all'

    @Test func summarizesMixedOutcomes() {
        let outcomes: [PackWriter.WriteOutcome] = [
            .written(bodyHash: "a"), .written(bodyHash: "b"),
            .written(bodyHash: "c"), .written(bodyHash: "d"), .conflict,
        ]
        let summary = PackWriter.summarize(outcomes)
        #expect(summary.synced == 4)
        #expect(summary.conflicts == 1)
        #expect(summary.description.contains("4 synced"))
        #expect(summary.description.contains("1 conflict"))
    }

    // MARK: — Idempotencia de escritura (AC#12 a nivel de fichero)

    @Test func rewritingSameBodyIsByteIdentical() throws {
        let f = try makeFixture()
        _ = PackWriter.write(request(f, body: "cuerpo estable"))
        let first = try #require(read(f.target))
        // Segunda escritura del mismo cuerpo (el destino sigue clean) → idéntico.
        _ = PackWriter.write(request(f, body: "cuerpo estable"))
        #expect(read(f.target) == first)
    }

    // MARK: — A2 (audit 360): destino que existe pero NO es UTF-8

    /// Un destino ilegible como UTF-8 se trataba como inexistente, así que ni
    /// disparaba el gate de conflicto ni se respaldaba: se perdía sin red. El
    /// caso no es teórico — un `CLAUDE.md` en Latin-1 con acentos lo reproduce.
    ///
    /// La rejilla barre las tres formas en que un destino puede no ser UTF-8, en
    /// vez de elegir un vector: un test que afirma "ningún destino existente se
    /// pierde" tiene que cubrir la región entera.
    @Test("Un destino no-UTF-8 es conflicto y NUNCA se pierde sin backup",
          arguments: [
            ("latin1-con-acentos", Data([0x63, 0x61, 0x66, 0xE9])),          // "café" en Latin-1
            ("binario-con-NUL",    Data([0x00, 0x01, 0x02, 0xFF, 0xFE])),
            ("utf8-truncado",      Data([0x68, 0x6F, 0x6C, 0x61, 0xC3])),    // 'Ã' a medias
          ])
    func nonUTF8TargetIsConflictAndBackedUp(caso: String, bytes: Data) throws {
        let f = try makeFixture()
        try bytes.write(to: f.target)

        // 1) Sin confirmación explícita, no se toca.
        #expect(PackWriter.write(request(f, body: "nuevo")) == .conflict,
                "\(caso): un destino ilegible es trabajo ajeno, no un destino ausente")
        #expect(try Data(contentsOf: f.target) == bytes,
                "\(caso): el destino se modificó pese a devolver .conflict")

        // 2) Con confirmación, se sobrescribe PERO queda respaldado byte a byte.
        let outcome = PackWriter.write(request(f, body: "nuevo", overwrite: true))
        guard case .written = outcome else {
            Issue.record("\(caso): esperaba .written con overwrite"); return
        }
        let subdir = PackWriter.backupSubdir(for: f.target, backupsRoot: f.backups)
        let backups = try FileManager.default
            .contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bak" }
        #expect(backups.count == 1, "\(caso): se sobrescribió sin dejar backup")
        #expect(try Data(contentsOf: try #require(backups.first)) == bytes,
                "\(caso): el backup no reproduce los bytes originales")
    }
}
