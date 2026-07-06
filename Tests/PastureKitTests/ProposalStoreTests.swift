import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — `ProposalStore` hace I/O sobre `~/.pasture/.inbox/`:
/// par `<uuid>.md` (payload) + `<uuid>.json` (metadata) atómico, expiración con
/// reloj inyectado, tolerancia a huérfanos/corrupción, dedupe. Reloj inyectado
/// (patrón `Freshness`). Directorio inbox inyectado (patrón `PackWriter`).
@Suite("ProposalStore — inbox I/O")
struct ProposalStoreTests {

    private let ref = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("save then loadPending round-trips proposal + payload")
    func saveThenLoadPendingRoundTrips() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        let p = Proposal.note(filename: "idea.md", collection: "agent",
                              content: "hello body", createdAt: ref, proposedBy: "Claude Code")
        try ProposalStore.save(p, payload: "hello body", inboxRoot: inbox)

        let pending = ProposalStore.loadPending(inboxRoot: inbox, now: ref)
        #expect(pending.count == 1)
        #expect(pending.first?.id == p.id)
        #expect(pending.first?.filename == "idea.md")
        #expect(ProposalStore.payload(for: p.id, inboxRoot: inbox) == "hello body")
    }

    @Test("save writes the .md + .json pair")
    func saveWritesPair() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        let p = Proposal.note(filename: "x.md", content: "body", createdAt: ref, proposedBy: "a")
        try ProposalStore.save(p, payload: "body", inboxRoot: inbox)

        let md = inbox.appendingPathComponent("\(p.id.uuidString).md")
        let json = inbox.appendingPathComponent("\(p.id.uuidString).json")
        #expect(FileManager.default.fileExists(atPath: md.path))
        #expect(FileManager.default.fileExists(atPath: json.path))
    }

    @Test("loadPending drops proposals older than the TTL and deletes their pair")
    func loadPendingSkipsExpired() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        let old = ref.addingTimeInterval(-Double(MCPLimits.proposalTTLDays + 1) * 86_400)
        let p = Proposal.note(filename: "old.md", content: "b", createdAt: old, proposedBy: "a")
        try ProposalStore.save(p, payload: "b", inboxRoot: inbox)

        let pending = ProposalStore.loadPending(inboxRoot: inbox, now: ref)
        #expect(pending.isEmpty)

        let json = inbox.appendingPathComponent("\(p.id.uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: json.path))
    }

    @Test("loadPending ignores an orphan .md without metadata")
    func loadPendingIgnoresOrphanMarkdown() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        try "loose".write(to: inbox.appendingPathComponent("\(UUID().uuidString).md"),
                          atomically: true, encoding: .utf8)

        #expect(ProposalStore.loadPending(inboxRoot: inbox, now: ref).isEmpty)
    }

    @Test("loadPending ignores corrupt metadata without crashing")
    func loadPendingIgnoresCorruptMetadata() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        let id = UUID().uuidString
        try "{ not valid json".write(to: inbox.appendingPathComponent("\(id).json"),
                                    atomically: true, encoding: .utf8)
        try "body".write(to: inbox.appendingPathComponent("\(id).md"),
                        atomically: true, encoding: .utf8)

        #expect(ProposalStore.loadPending(inboxRoot: inbox, now: ref).isEmpty)
    }

    @Test("contains dedupes by payload hash AND destination")
    func containsDedupes() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        let p = Proposal.note(filename: "idea.md", collection: "agent",
                              content: "same", createdAt: ref, proposedBy: "a")
        try ProposalStore.save(p, payload: "same", inboxRoot: inbox)

        let hash = Proposal.payloadHash(for: "same")
        #expect(ProposalStore.contains(payloadHash: hash, destinationKey: p.destinationKey, inboxRoot: inbox))
        // Distinto payload → no es duplicado.
        #expect(!ProposalStore.contains(payloadHash: Proposal.payloadHash(for: "other"),
                                       destinationKey: p.destinationKey, inboxRoot: inbox))
        // Mismo payload, distinto destino → no es duplicado.
        let otherDest = Proposal.note(filename: "diff.md", content: "same", proposedBy: "a").destinationKey
        #expect(!ProposalStore.contains(payloadHash: hash, destinationKey: otherDest, inboxRoot: inbox))
    }

    @Test("delete removes the pair")
    func deleteRemovesPair() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        let p = Proposal.note(filename: "x.md", content: "b", createdAt: ref, proposedBy: "a")
        try ProposalStore.save(p, payload: "b", inboxRoot: inbox)
        ProposalStore.delete(id: p.id, inboxRoot: inbox)

        #expect(ProposalStore.loadPending(inboxRoot: inbox, now: ref).isEmpty)
        #expect(ProposalStore.payload(for: p.id, inboxRoot: inbox) == nil)
    }

    @Test("pendingCount reflects saved proposals")
    func pendingCountReflectsSaved() throws {
        let inbox = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: inbox) }

        try ProposalStore.save(Proposal.note(filename: "a.md", content: "1", createdAt: ref, proposedBy: "x"),
                              payload: "1", inboxRoot: inbox)
        try ProposalStore.save(Proposal.note(filename: "b.md", content: "2", createdAt: ref, proposedBy: "x"),
                              payload: "2", inboxRoot: inbox)

        #expect(ProposalStore.pendingCount(inboxRoot: inbox, now: ref) == 2)
    }
}
