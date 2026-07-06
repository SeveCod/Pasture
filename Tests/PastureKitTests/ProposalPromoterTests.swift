import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — `ProposalPromoter` es el ÚNICO write-path al vault visible,
/// invocado solo desde la GUI. Valida el destino con la misma doble capa que la
/// lectura (SEC-M1 + SEC-M2), antepone frontmatter de procedencia a las notas, y
/// para los append detecta que el destino cambió desde que se propuso.
@Suite("ProposalPromoter — promoción al vault")
struct ProposalPromoterTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Prepara un inbox temporal con una propuesta ya guardada (payload incluido).
    private func stage(_ proposal: Proposal, payload: String) throws -> URL {
        let inbox = try makeTempDirectory()
        try ProposalStore.save(proposal, payload: payload, inboxRoot: inbox)
        return inbox
    }

    // MARK: — promoteNote

    @Test("promoteNote creates the file with provenance frontmatter")
    func promoteNoteCreatesFileWithProvenance() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let p = Proposal.note(filename: "idea.md", collection: "agent",
                             content: "the body", createdAt: now, proposedBy: "Claude Code")
        let inbox = try stage(p, payload: "the body")
        defer { try? FileManager.default.removeItem(at: inbox) }

        let result = ProposalPromoter.promoteNote(p, inboxRoot: inbox, vaultRoot: vault, now: now)
        let url = try #require(try result.get())

        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(written.contains("origin: agent"))
        #expect(written.contains("proposed_by: Claude Code"))
        #expect(written.contains("the body"))
        #expect(url.pathComponents.contains("agent"))       // colección destino
        #expect(url.lastPathComponent == "idea.md")
    }

    @Test("promoteNote strips reserved frontmatter keys from the agent payload")
    func promoteNoteStripsReservedPayloadKeys() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let payload = "---\nreview_after: 2099-01-01\nttl: 99999\ngenerated: true\nsource: /tmp/evil\n---\nreal content"
        let p = Proposal.note(filename: "x.md", content: payload, createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: payload)
        defer { try? FileManager.default.removeItem(at: inbox) }

        let url = try ProposalPromoter.promoteNote(p, inboxRoot: inbox, vaultRoot: vault, now: now).get()
        let written = try String(contentsOf: url, encoding: .utf8)
        let fm = FrontmatterParser.parse(written).frontmatter
        // Las claves de frescura/source/generated del agente NO sobreviven.
        #expect(fm?.reviewAfter == nil)
        #expect(fm?.ttlDays == nil)
        #expect(fm?.generated == false)
        #expect(fm?.source == nil)
        // La procedencia sí se antepone y el cuerpo se conserva.
        #expect(written.contains("origin: agent"))
        #expect(written.contains("real content"))
    }

    @Test("promoteNote deduplicates the filename on collision")
    func promoteNoteDeduplicatesName() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        try "existing".write(to: vault.appendingPathComponent("idea.md"), atomically: true, encoding: .utf8)

        let p = Proposal.note(filename: "idea.md", content: "new", createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "new")
        defer { try? FileManager.default.removeItem(at: inbox) }

        let url = try ProposalPromoter.promoteNote(p, inboxRoot: inbox, vaultRoot: vault, now: now).get()
        #expect(url.lastPathComponent == "idea-2.md")
    }

    @Test("promoteNote removes the inbox pair")
    func promoteNoteRemovesInboxPair() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let p = Proposal.note(filename: "x.md", content: "b", createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "b")
        defer { try? FileManager.default.removeItem(at: inbox) }

        _ = try ProposalPromoter.promoteNote(p, inboxRoot: inbox, vaultRoot: vault, now: now).get()
        #expect(ProposalStore.loadPending(inboxRoot: inbox, now: now).isEmpty)
    }

    @Test("promoteNote rejects a destination outside the vault")
    func promoteNoteRejectsOutsideVault() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let p = Proposal.note(filename: "x.md", collection: "../evil",
                             content: "b", createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "b")
        defer { try? FileManager.default.removeItem(at: inbox) }

        let result = ProposalPromoter.promoteNote(p, inboxRoot: inbox, vaultRoot: vault, now: now)
        #expect(result == .failure(.outsideVault))
    }

    // MARK: — promoteAppend

    @Test("promoteAppend appends with a blank-line separator when the hash matches")
    func promoteAppendMatchingHash() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let target = vault.appendingPathComponent("log.md")
        try "line 1".write(to: target, atomically: true, encoding: .utf8)

        let p = Proposal.append(relativePath: "log.md", content: "line 2",
                               targetHash: SyncMarker.sha256("line 1"),
                               createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "line 2")
        defer { try? FileManager.default.removeItem(at: inbox) }

        _ = try ProposalPromoter.promoteAppend(p, inboxRoot: inbox, vaultRoot: vault).get()
        #expect(try String(contentsOf: target, encoding: .utf8) == "line 1\n\nline 2")
    }

    @Test("promoteAppend reports hash mismatch when the target changed")
    func promoteAppendHashMismatch() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let target = vault.appendingPathComponent("log.md")
        try "line 1".write(to: target, atomically: true, encoding: .utf8)
        // targetHash grabado sobre un contenido distinto al actual → mismatch.
        let p = Proposal.append(relativePath: "log.md", content: "x",
                               targetHash: SyncMarker.sha256("STALE"),
                               createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "x")
        defer { try? FileManager.default.removeItem(at: inbox) }

        let result = ProposalPromoter.promoteAppend(p, inboxRoot: inbox, vaultRoot: vault)
        #expect(result == .failure(.hashMismatch(currentContent: "line 1")))
        // No debe haber tocado el destino.
        #expect(try String(contentsOf: target, encoding: .utf8) == "line 1")
    }

    @Test("promoteAppend with override appends to current content despite a hash mismatch")
    func promoteAppendOverrideDespiteMismatch() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let target = vault.appendingPathComponent("log.md")
        try "changed content".write(to: target, atomically: true, encoding: .utf8)
        // targetHash de un contenido viejo → mismatch, pero con override se anexa igual.
        let p = Proposal.append(relativePath: "log.md", content: "line 2",
                               targetHash: SyncMarker.sha256("old content"),
                               createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "line 2")
        defer { try? FileManager.default.removeItem(at: inbox) }

        _ = try ProposalPromoter.promoteAppend(p, inboxRoot: inbox, vaultRoot: vault,
                                               overrideChangedTarget: true).get()
        #expect(try String(contentsOf: target, encoding: .utf8) == "changed content\n\nline 2")
    }

    @Test("promoteAppend fails if the target is missing")
    func promoteAppendTargetMissing() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let p = Proposal.append(relativePath: "nope.md", content: "x",
                               targetHash: "h", createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "x")
        defer { try? FileManager.default.removeItem(at: inbox) }

        #expect(ProposalPromoter.promoteAppend(p, inboxRoot: inbox, vaultRoot: vault) == .failure(.targetMissing))
    }

    // MARK: — reject

    @Test("reject removes the pair without touching the vault")
    func rejectRemovesPair() throws {
        let vault = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let p = Proposal.note(filename: "x.md", content: "b", createdAt: now, proposedBy: "a")
        let inbox = try stage(p, payload: "b")
        defer { try? FileManager.default.removeItem(at: inbox) }

        ProposalPromoter.reject(p, inboxRoot: inbox)
        #expect(ProposalStore.loadPending(inboxRoot: inbox, now: now).isEmpty)
    }
}
