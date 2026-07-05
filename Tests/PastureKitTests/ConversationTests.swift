import Testing
@testable import PastureKit
import Foundation

// Word of N alphanumerics estimates to max(1, N/4) tokens (see TokenEstimator).
private func word(_ chars: Int) -> String { String(repeating: "a", count: chars) }

private func model(window: Int, maxOut: Int) -> AIModel {
    AIModel(id: "t", displayName: "t", provider: .anthropic,
            contextWindow: window, inputCostPer1M: 0, outputCostPer1M: 0, maxOutputTokens: maxOut)
}

// MARK: - ConversationTruncator

@Suite struct ConversationTruncatorTests {

    // budget = floor(0.95 * window) - maxOut

    @Test func keepsAllWhenWithinBudget() {
        let m = model(window: 1000, maxOut: 200) // budget 750
        let msgs = [
            ChatMessage(role: .user, content: word(40)),      // 10t (context)
            ChatMessage(role: .assistant, content: word(40)), // 10t
            ChatMessage(role: .user, content: word(40)),      // 10t
        ]
        #expect(ConversationTruncator.truncate(msgs, model: m) == msgs)
    }

    @Test func dropsOldestMiddleWhenOverBudget() {
        let m = model(window: 1000, maxOut: 200) // budget 750
        let ctx = ChatMessage(role: .user, content: word(400))       // 100t
        let old = ChatMessage(role: .assistant, content: word(2000)) // 500t
        let recent = ChatMessage(role: .user, content: word(2000))   // 500t
        let last = ChatMessage(role: .user, content: word(400))      // 100t
        // total 1200 > 750; dropping `old` leaves 700 <= 750
        let result = ConversationTruncator.truncate([ctx, old, recent, last], model: m)
        #expect(result.count == 3)
        #expect(result.first == ctx)
        #expect(result.last == last)
        #expect(!result.contains(old))
        #expect(result.contains(recent))
    }

    @Test func neverDropsContextOrLastEvenWhenStillOverBudget() {
        let m = model(window: 100, maxOut: 40) // budget 55
        let ctx = ChatMessage(role: .user, content: word(4000))       // 1000t
        let mid = ChatMessage(role: .assistant, content: word(4000))  // 1000t
        let last = ChatMessage(role: .user, content: word(4000))      // 1000t
        let result = ConversationTruncator.truncate([ctx, mid, last], model: m)
        #expect(result.count == 2)
        #expect(result.first == ctx)
        #expect(result.last == last)
    }

    @Test func twoMessageConversationReturnedUnchanged() {
        let m = model(window: 100, maxOut: 40) // budget 55
        let ctx = ChatMessage(role: .user, content: word(4000))  // 1000t
        let last = ChatMessage(role: .user, content: word(4000)) // 1000t
        let result = ConversationTruncator.truncate([ctx, last], model: m)
        #expect(result == [ctx, last])
    }

    @Test func singleMessageReturnedUnchanged() {
        let m = model(window: 100, maxOut: 40)
        let only = ChatMessage(role: .user, content: word(4000))
        #expect(ConversationTruncator.truncate([only], model: m) == [only])
    }

    @Test func emptyReturnsEmpty() {
        let m = model(window: 1000, maxOut: 200)
        #expect(ConversationTruncator.truncate([], model: m).isEmpty)
    }
}

// MARK: - ConversationComposer.wire (context embedding, AC#1–3)

@Suite struct ConversationComposerWireTests {

    @Test func embedsContextIntoFirstUserOnly() {
        let transcript = [
            ChatMessage(role: .user, content: "q1"),
            ChatMessage(role: .assistant, content: "a1"),
            ChatMessage(role: .user, content: "q2"),
        ]
        let wired = ConversationComposer.wire(transcript: transcript, context: "CTX")
        #expect(wired.count == 3)
        #expect(wired[0].content == "CTX\n\nq1")
        #expect(wired[1].content == "a1")
        #expect(wired[2].content == "q2")
    }

    @Test func preservesIDsAndRoles() {
        let first = ChatMessage(role: .user, content: "q1")
        let wired = ConversationComposer.wire(transcript: [first], context: "CTX")
        #expect(wired[0].id == first.id)
        #expect(wired[0].role == .user)
    }

    @Test func emptyContextLeavesTranscriptUnchanged() {
        let transcript = [
            ChatMessage(role: .user, content: "q1"),
            ChatMessage(role: .assistant, content: "a1"),
        ]
        #expect(ConversationComposer.wire(transcript: transcript, context: "") == transcript)
    }

    @Test func emptyTranscriptReturnsEmpty() {
        #expect(ConversationComposer.wire(transcript: [], context: "CTX").isEmpty)
    }
}

// MARK: - ConversationComposer.distill (transcript -> vault .md)

@Suite struct ConversationDistillerTests {

    @Test func rendersQuestionAndAnswerHeadings() {
        let t = [
            ChatMessage(role: .user, content: "What is X?"),
            ChatMessage(role: .assistant, content: "X is Y."),
        ]
        let md = ConversationComposer.distill(t)
        #expect(md.contains("## Question"))
        #expect(md.contains("What is X?"))
        #expect(md.contains("## Answer"))
        #expect(md.contains("X is Y."))
    }

    @Test func marksIncompleteAnswers() {
        let t = [
            ChatMessage(role: .user, content: "q"),
            ChatMessage(role: .assistant, content: "partial", isComplete: false),
        ]
        let md = ConversationComposer.distill(t)
        #expect(md.localizedCaseInsensitiveContains("incomplete"))
    }

    @Test func preservesTurnOrder() {
        let t = [
            ChatMessage(role: .user, content: "FIRST_Q"),
            ChatMessage(role: .assistant, content: "FIRST_A"),
            ChatMessage(role: .user, content: "SECOND_Q"),
        ]
        let md = ConversationComposer.distill(t)
        let iFirstQ = try! #require(md.range(of: "FIRST_Q")).lowerBound
        let iFirstA = try! #require(md.range(of: "FIRST_A")).lowerBound
        let iSecondQ = try! #require(md.range(of: "SECOND_Q")).lowerBound
        #expect(iFirstQ < iFirstA)
        #expect(iFirstA < iSecondQ)
    }

    @Test func emptyTranscriptGivesEmptyString() {
        #expect(ConversationComposer.distill([]).isEmpty)
    }
}

// MARK: - AskConversation (transcript state machine)

@Suite struct AskConversationTests {

    @Test func startsEmpty() {
        #expect(AskConversation().isEmpty)
    }

    @Test func addUserQuestionAppendsUserMessage() {
        var c = AskConversation()
        c.addUserQuestion("hi")
        #expect(c.messages.count == 1)
        #expect(c.messages[0].role == .user)
        #expect(c.messages[0].content == "hi")
    }

    @Test func requestMessagesEmbedsContextInFirstUser() {
        var c = AskConversation()
        c.addUserQuestion("q1")
        let wire = c.requestMessages(context: "CTX", model: model(window: 200_000, maxOut: 8192))
        #expect(wire[0].content == "CTX\n\nq1")
        // stored transcript stays clean
        #expect(c.messages[0].content == "q1")
    }

    @Test func liveAssistantTurnAccumulatesDeltas() {
        var c = AskConversation()
        c.addUserQuestion("q")
        c.beginAssistant()
        c.appendDelta("Hel")
        c.appendDelta("lo")
        #expect(c.messages.count == 2)
        #expect(c.messages[1].role == .assistant)
        #expect(c.messages[1].content == "Hello")
        #expect(c.messages[1].isComplete == false)
    }

    @Test func completeAssistantMarksComplete() {
        var c = AskConversation()
        c.addUserQuestion("q")
        c.beginAssistant()
        c.appendDelta("done")
        c.completeAssistant()
        #expect(c.messages[1].isComplete == true)
    }

    @Test func interruptedEmptyAssistantIsDropped() {
        var c = AskConversation()
        c.addUserQuestion("q")
        c.beginAssistant()
        c.endInterruptedAssistant()
        #expect(c.messages.count == 1) // empty placeholder removed
        #expect(c.messages[0].role == .user)
    }

    @Test func interruptedPartialAssistantStaysIncomplete() {
        var c = AskConversation()
        c.addUserQuestion("q")
        c.beginAssistant()
        c.appendDelta("partial")
        c.endInterruptedAssistant()
        #expect(c.messages.count == 2)
        #expect(c.messages[1].content == "partial")
        #expect(c.messages[1].isComplete == false)
    }

    @Test func multipleTurnsAccumulateWithoutClearing() {
        var c = AskConversation()
        c.addUserQuestion("q1")
        c.beginAssistant(); c.appendDelta("a1"); c.completeAssistant()
        c.addUserQuestion("q2")
        c.beginAssistant(); c.appendDelta("a2"); c.completeAssistant()
        #expect(c.messages.count == 4)
        #expect(c.messages.map(\.content) == ["q1", "a1", "q2", "a2"])
    }

    @Test func clearEmptiesTranscript() {
        var c = AskConversation()
        c.addUserQuestion("q")
        c.clear()
        #expect(c.isEmpty)
    }
}
