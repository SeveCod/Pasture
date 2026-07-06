import Testing
@testable import PastureKit

/// v1.8 Memory Inbox — caps del camino de propuestas (SEC-M14/M15). El threat
/// model exige que EXISTA un límite en cada eje; el valor es un default defendible.
@Suite("MCPLimits — proposal caps")
struct MCPLimitsTests {

    @Test("maxProposalBytes is 1 MB (SEC-M14)")
    func maxProposalBytesIsOneMegabyte() {
        #expect(MCPLimits.maxProposalBytes == 1_000_000)
    }

    @Test("maxPendingProposals is 50 (SEC-M15)")
    func maxPendingProposalsIsFifty() {
        #expect(MCPLimits.maxPendingProposals == 50)
    }

    @Test("proposalTTLDays is 14")
    func proposalTTLDaysIsFourteen() {
        #expect(MCPLimits.proposalTTLDays == 14)
    }
}
