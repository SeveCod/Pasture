import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — tools de escritura `propose_note`/`propose_append`. Solo
/// existen en el catálogo con `allowProposals`. Nunca escriben en el vault: dejan
/// un par en `~/.pasture/.inbox/`. Validación de destino (doble capa), sanitizado
/// de nombre, caps (tamaño/pendientes), dedupe y aviso de secretos.
@Suite("MCPTools — proposal write-path")
struct MCPProposalToolsTests {

    private func makeVault(allowProposals: Bool = true) -> (MCPServerConfig, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-propose-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (MCPServerConfig(vaultRoot: root, feedFormat: .xml, allowProposals: allowProposals), root)
    }

    private func inbox(_ root: URL) -> URL { root.appendingPathComponent(".inbox", isDirectory: true) }
    private func text(_ r: ToolCallResult) -> String { r.content.map(\.text).joined(separator: "\n") }

    // MARK: — Catálogo condicional (regresión de solo-lectura)

    @Test("proposal tools are hidden when proposals are disabled")
    func catalogHidesProposalToolsWhenDisabled() {
        let names = MCPTools.catalog(includingProposals: false).tools.map(\.name)
        #expect(!names.contains("propose_note"))
        #expect(!names.contains("propose_append"))
        #expect(names.count == 4)
    }

    @Test("proposal tools appear when proposals are enabled")
    func catalogShowsProposalToolsWhenEnabled() {
        let names = MCPTools.catalog(includingProposals: true).tools.map(\.name)
        #expect(names.contains("propose_note"))
        #expect(names.contains("propose_append"))
        #expect(names.count == 6)
    }

    // MARK: — Gating por allowProposals

    @Test("run rejects propose_note as unknown when proposals are disabled")
    func runRejectsProposeNoteWhenDisabled() {
        let (config, _) = makeVault(allowProposals: false)
        let params = JSONValue.object([
            "name": .string("propose_note"),
            "arguments": .object(["filename": .string("x.md"), "content": .string("body")]),
        ])
        let result = MCPTools.run(params: params, config: config, proposedBy: "Claude Code")
        #expect(result.isError)
    }

    // MARK: — propose_note

    @Test("propose_note stores a proposal carrying its provenance")
    func proposeNoteStoresProposalWithProvenance() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = MCPTools.proposeNote(
            arguments: .object(["filename": .string("idea.md"), "collection": .string("agent"),
                               "content": .string("the body")]),
            config: config, proposedBy: "Claude Code")
        #expect(!result.isError)

        let pending = ProposalStore.loadPending(inboxRoot: inbox(root))
        #expect(pending.count == 1)
        #expect(pending.first?.proposedBy == "Claude Code")
        #expect(pending.first?.filename == "idea.md")
        #expect(pending.first?.collection == "agent")
        #expect(ProposalStore.payload(for: pending.first!.id, inboxRoot: inbox(root)) == "the body")
    }

    @Test("propose_note rejects content over the size cap")
    func proposeNoteRejectsOversized() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let huge = String(repeating: "a", count: MCPLimits.maxProposalBytes + 1)
        let result = MCPTools.proposeNote(
            arguments: .object(["filename": .string("big.md"), "content": .string(huge)]),
            config: config, proposedBy: "a")
        #expect(result.isError)
        #expect(ProposalStore.loadPending(inboxRoot: inbox(root)).isEmpty)
    }

    @Test("propose_note dedupes an identical proposal")
    func proposeNoteDedupes() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let args = JSONValue.object(["filename": .string("idea.md"), "content": .string("same")])
        _ = MCPTools.proposeNote(arguments: args, config: config, proposedBy: "a")
        let second = MCPTools.proposeNote(arguments: args, config: config, proposedBy: "a")
        #expect(second.isError)
        #expect(ProposalStore.loadPending(inboxRoot: inbox(root)).count == 1)
    }

    @Test("propose_note rejects a collection outside the vault")
    func proposeNoteRejectsCollectionOutsideVault() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = MCPTools.proposeNote(
            arguments: .object(["filename": .string("x.md"), "collection": .string("../evil"),
                               "content": .string("b")]),
            config: config, proposedBy: "a")
        #expect(result.isError)
        #expect(ProposalStore.loadPending(inboxRoot: inbox(root)).isEmpty)
    }

    @Test("propose_note warns on secrets but still stores")
    func proposeNoteWarnsOnSecrets() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = "aws key " + "AKIA" + "IOSFODNN7EXAMPLE"
        let result = MCPTools.proposeNote(
            arguments: .object(["filename": .string("creds.md"), "content": .string(secret)]),
            config: config, proposedBy: "a")
        #expect(!result.isError)
        #expect(result.warning != nil)
        let pending = ProposalStore.loadPending(inboxRoot: inbox(root))
        #expect(pending.first?.secretSummary != nil)
    }

    @Test("propose refuses new proposals when the inbox is full")
    func proposeRejectsWhenInboxFull() throws {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        // Rellena el inbox al tope con propuestas distintas.
        for i in 0..<MCPLimits.maxPendingProposals {
            let p = Proposal.note(filename: "f\(i).md", content: "c\(i)", proposedBy: "a")
            try ProposalStore.save(p, payload: "c\(i)", inboxRoot: inbox(root))
        }
        let result = MCPTools.proposeNote(
            arguments: .object(["filename": .string("extra.md"), "content": .string("more")]),
            config: config, proposedBy: "a")
        #expect(result.isError)
    }

    // MARK: — propose_append

    @Test("propose_append stores the target hash of the current destination")
    func proposeAppendStoresWithTargetHash() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        try? "line 1".write(to: root.appendingPathComponent("log.md"), atomically: true, encoding: .utf8)

        let result = MCPTools.proposeAppend(
            arguments: .object(["path": .string("log.md"), "content": .string("line 2")]),
            config: config, proposedBy: "a")
        #expect(!result.isError)
        let pending = ProposalStore.loadPending(inboxRoot: inbox(root))
        #expect(pending.first?.kind == .append)
        #expect(pending.first?.targetHash == SyncMarker.sha256("line 1"))
    }

    @Test("propose_append rejects a missing target")
    func proposeAppendRejectsMissingTarget() {
        let (config, root) = makeVault()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = MCPTools.proposeAppend(
            arguments: .object(["path": .string("nope.md"), "content": .string("x")]),
            config: config, proposedBy: "a")
        #expect(result.isError)
        #expect(ProposalStore.loadPending(inboxRoot: inbox(root)).isEmpty)
    }
}
