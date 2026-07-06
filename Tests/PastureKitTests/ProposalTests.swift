import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — `Proposal` es el schema en disco (schemaVersion=1) de una
/// propuesta de escritura del agente MCP: procedencia, hashes y campo reservado
/// `autoApproved` (Fase 2). Tipo de valor puro, sin I/O.
@Suite("Proposal value type")
struct ProposalTests {

    // MARK: — Round-trip Codable

    @Test("Codable round-trip preserves .note fields")
    func codableRoundTripPreservesNoteFields() throws {
        let original = Proposal(
            schemaVersion: 1,
            kind: .note,
            filename: "idea.md",
            collection: "agent",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            proposedBy: "Claude Code",
            secretSummary: nil,
            payloadHash: Proposal.payloadHash(for: "body")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Proposal.self, from: data)

        #expect(decoded == original)

        let set: Set<Proposal> = [original, decoded]
        #expect(set.count == 1)
    }

    @Test("Codable round-trip preserves .append fields")
    func codableRoundTripPreservesAppendFields() throws {
        let original = Proposal(
            schemaVersion: 1,
            kind: .append,
            relativePath: "notes/log.md",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            proposedBy: "Claude Desktop",
            targetHash: "abc123",
            payloadHash: Proposal.payloadHash(for: "line")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Proposal.self, from: data)

        #expect(decoded == original)
        #expect(decoded.relativePath == "notes/log.md")
        #expect(decoded.targetHash == "abc123")
        #expect(decoded.filename == nil)
        #expect(decoded.collection == nil)
    }

    // MARK: — schemaVersion

    @Test("schemaVersion defaults to 1 and is emitted explicitly")
    func schemaVersionDefaultsToOneAndIsEmittedExplicitly() throws {
        #expect(Proposal.currentSchemaVersion == 1)

        let p = Proposal(
            kind: .note,
            filename: "x.md",
            proposedBy: "agent",
            payloadHash: Proposal.payloadHash(for: "x")
        )
        #expect(p.schemaVersion == 1)

        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(json.contains("\"schemaVersion\":1"))
    }

    // MARK: — autoApproved (reservado Fase 2, forward/backward-compat)

    @Test("autoApproved decodes absent as nil and present as value")
    func autoApprovedDecodesAbsentAsNilAndPresentAsValue() throws {
        let absent = """
        {"schemaVersion":1,"id":"\(UUID().uuidString)","kind":"note","filename":"a.md","createdAt":0,"proposedBy":"agent","payloadHash":"h"}
        """
        let decodedAbsent = try JSONDecoder().decode(Proposal.self, from: Data(absent.utf8))
        #expect(decodedAbsent.autoApproved == nil)

        let present = """
        {"schemaVersion":1,"id":"\(UUID().uuidString)","kind":"note","filename":"a.md","createdAt":0,"proposedBy":"agent","payloadHash":"h","autoApproved":true}
        """
        let decodedPresent = try JSONDecoder().decode(Proposal.self, from: Data(present.utf8))
        #expect(decodedPresent.autoApproved == true)
    }

    // MARK: — payloadHash canónico

    @Test("payloadHash is deterministic and matches SyncMarker")
    func payloadHashHelperIsDeterministicAndMatchesSyncMarker() {
        #expect(Proposal.payloadHash(for: "hello") == SyncMarker.sha256("hello"))
        #expect(Proposal.payloadHash(for: "hello") == Proposal.payloadHash(for: "hello"))
    }

    // MARK: — Factories (invariante kind ↔ campos de destino)

    @Test("note factory populates note destination and hash")
    func noteFactoryPopulatesNoteDestinationAndHash() {
        let p = Proposal.note(
            filename: "idea.md",
            collection: "agent",
            content: "body",
            proposedBy: "Claude Code"
        )
        #expect(p.kind == .note)
        #expect(p.filename == "idea.md")
        #expect(p.collection == "agent")
        #expect(p.relativePath == nil)
        #expect(p.targetHash == nil)
        #expect(p.payloadHash == SyncMarker.sha256("body"))
        #expect(p.schemaVersion == 1)
    }

    @Test("append factory populates append destination and hash")
    func appendFactoryPopulatesAppendDestinationAndHash() {
        let p = Proposal.append(
            relativePath: "notes/log.md",
            content: "line",
            targetHash: "abc",
            proposedBy: "Claude Desktop"
        )
        #expect(p.kind == .append)
        #expect(p.relativePath == "notes/log.md")
        #expect(p.filename == nil)
        #expect(p.collection == nil)
        #expect(p.targetHash == "abc")
        #expect(p.payloadHash == SyncMarker.sha256("line"))
    }
}
