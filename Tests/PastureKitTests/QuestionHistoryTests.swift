import Testing
@testable import PastureKit
import Foundation

@Suite struct QuestionHistoryTests {

    @Test func loadReturnsEmptyWhenUnset() {
        let defaults = makeIsolatedUserDefaults()
        #expect(QuestionHistory.load(from: defaults).isEmpty)
    }

    @Test func recordInsertsMostRecentFirst() {
        let defaults = makeIsolatedUserDefaults()
        QuestionHistory.record("first", in: defaults)
        QuestionHistory.record("second", in: defaults)
        #expect(QuestionHistory.load(from: defaults) == ["second", "first"])
    }

    @Test func recordTrimsWhitespaceAndIgnoresEmpty() {
        let defaults = makeIsolatedUserDefaults()
        QuestionHistory.record("  padded  ", in: defaults)
        QuestionHistory.record("   ", in: defaults)
        QuestionHistory.record("", in: defaults)
        #expect(QuestionHistory.load(from: defaults) == ["padded"])
    }

    @Test func recordDeduplicatesMovingEntryToFront() {
        let defaults = makeIsolatedUserDefaults()
        QuestionHistory.record("a", in: defaults)
        QuestionHistory.record("b", in: defaults)
        QuestionHistory.record("a", in: defaults)
        #expect(QuestionHistory.load(from: defaults) == ["a", "b"])
    }

    @Test func recordCapsAtMaxEntries() {
        let defaults = makeIsolatedUserDefaults()
        for i in 1...(QuestionHistory.maxEntries + 5) {
            QuestionHistory.record("question \(i)", in: defaults)
        }
        let entries = QuestionHistory.load(from: defaults)
        #expect(entries.count == QuestionHistory.maxEntries)
        #expect(entries.first == "question \(QuestionHistory.maxEntries + 5)")
        #expect(entries.last == "question 6")
    }

    @Test func clearRemovesAllEntries() {
        let defaults = makeIsolatedUserDefaults()
        QuestionHistory.record("something", in: defaults)
        QuestionHistory.clear(in: defaults)
        #expect(QuestionHistory.load(from: defaults).isEmpty)
    }
}
