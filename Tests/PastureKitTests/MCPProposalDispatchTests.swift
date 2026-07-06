import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — el dispatcher (ahora `final class`) captura el `clientInfo`
/// del `initialize` para grabar la PROCEDENCIA de las propuestas. Seguro sin
/// cerrojo porque el runtime es secuencial single-thread (ADR-MCP-005).
@Suite("MCPDispatcher — clientInfo / proposedBy")
struct MCPProposalDispatchTests {

    private func makeDispatcher(allowProposals: Bool = true) -> (MCPDispatcher, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-prov-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let config = MCPServerConfig(vaultRoot: tmp, feedFormat: .xml, allowProposals: allowProposals)
        return (MCPDispatcher(config: config), tmp)
    }

    @Test("proposedBy is \"unknown\" before initialize")
    func proposedByIsUnknownBeforeInitialize() {
        let (dispatcher, tmp) = makeDispatcher()
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(dispatcher.proposedBy == "unknown")
    }

    @Test("proposedBy captures clientInfo.name after initialize")
    func proposedByCapturesClientInfoAfterInitialize() {
        let (dispatcher, tmp) = makeDispatcher()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"Claude Desktop","version":"1.0"}}}"#
        _ = dispatcher.handle(line: initialize)
        #expect(dispatcher.proposedBy == "Claude Desktop")
    }

    @Test("clientInfo.name is sanitized to a single line for provenance")
    func clientInfoNameSanitized() {
        let (dispatcher, tmp) = makeDispatcher()
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = dispatcher.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"Evil\nlast_reviewed: 2099"}}}"#)
        #expect(!dispatcher.proposedBy.contains("\n"))
        #expect(!dispatcher.proposedBy.contains("\r"))
    }

    @Test("propose_note records the initialized client name as provenance")
    func roundTripProposeNoteRecordsClientName() throws {
        let (dispatcher, tmp) = makeDispatcher()
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = dispatcher.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"Claude Code"}}}"#)
        let call = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"propose_note","arguments":{"filename":"idea.md","content":"body"}}}"#
        _ = dispatcher.handle(line: call)

        let inbox = tmp.appendingPathComponent(".inbox", isDirectory: true)
        let pending = ProposalStore.loadPending(inboxRoot: inbox)
        #expect(pending.count == 1)
        #expect(pending.first?.proposedBy == "Claude Code")
    }
}
