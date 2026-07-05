import Foundation

/// The state machine behind Ask's multi-turn transcript. Pure and value-typed so
/// it is fully testable; `AskViewModel` owns one and drives it as the stream runs.
///
/// The stored `messages` are the *clean* transcript (questions and answers, no
/// file context). The live assistant turn is the last message with
/// `isComplete == false`; deltas append to it, and it is either completed or,
/// if interrupted, dropped-when-empty / left-flagged-when-partial (AC#2–3).
public struct AskConversation: Sendable, Equatable {
    public private(set) var messages: [ChatMessage] = []

    public init() {}

    public var isEmpty: Bool { messages.isEmpty }

    /// Records a new user question at the end of the transcript.
    public mutating func addUserQuestion(_ text: String) {
        messages.append(ChatMessage(role: .user, content: text))
    }

    /// The payload to send for the current transcript: context embedded into the
    /// first user message (AC#1–3), then truncated to the model budget. Pure —
    /// does not mutate the stored transcript.
    public func requestMessages(context: String, model: AIModel) -> [ChatMessage] {
        ConversationTruncator.truncate(
            ConversationComposer.wire(transcript: messages, context: context),
            model: model
        )
    }

    /// Opens a live (empty, incomplete) assistant turn that deltas append to.
    public mutating func beginAssistant() {
        messages.append(ChatMessage(role: .assistant, content: "", isComplete: false))
    }

    /// Appends streamed text to the live assistant turn.
    public mutating func appendDelta(_ text: String) {
        guard let last = lastAssistantIndex else { return }
        messages[last].content += text
    }

    /// Marks the live assistant turn finished.
    public mutating func completeAssistant() {
        guard let last = lastAssistantIndex else { return }
        messages[last].isComplete = true
    }

    /// Ends an interrupted assistant turn (Stop pressed, or the stream failed):
    /// an empty turn is removed; a partial one stays flagged incomplete so it
    /// still travels back as history.
    public mutating func endInterruptedAssistant() {
        guard let last = lastAssistantIndex else { return }
        if messages[last].content.isEmpty {
            messages.remove(at: last)
        }
    }

    public mutating func clear() {
        messages.removeAll()
    }

    private var lastAssistantIndex: Int? {
        guard let last = messages.indices.last, messages[last].role == .assistant else { return nil }
        return last
    }
}
