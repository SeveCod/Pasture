import SwiftUI
import AppKit
import PastureKit

@MainActor
final class AskViewModel: ObservableObject {
    @Published var question = ""
    /// The multi-turn transcript (clean: questions/answers, no file context).
    /// The live assistant turn is the last message while `isStreaming`.
    @Published private(set) var conversation = AskConversation()
    @Published var isStreaming = false
    @Published var error: AIClientError?
    @Published private(set) var selectedProvider: AIProviderKind = AISettings.loadProvider()
    @Published private(set) var selectedModelID: String = AISettings.loadModelID()
    @Published private(set) var hasAPIKey: Bool = false
    @Published private(set) var questionHistory: [String] = QuestionHistory.load()

    static let responseFilenamePrefixLength = 40

    private let client = AIClient.shared
    private var streamTask: Task<Void, Never>?

    init() {
        hasAPIKey = AISettings.loadAPIKey(for: selectedProvider) != nil
    }

    var resolvedModel: AIModel {
        AIModel.resolve(id: selectedModelID, preferredProvider: selectedProvider)
    }

    var canSend: Bool {
        !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming && hasAPIKey
    }

    /// True once at least one turn exists — drives the action bar and Clear button.
    var hasConversation: Bool { !conversation.isEmpty }

    /// The whole conversation rendered as Markdown, for copy / save / export.
    var distilledConversation: String { ConversationComposer.distill(conversation.messages) }

    func inputTokenEstimate(for contextTokens: Int) -> Int {
        TokenEstimator.inputTokenEstimate(contextTokens: contextTokens, question: question)
    }

    func costEstimate(for contextTokens: Int) -> String {
        TokenEstimator.costEstimate(contextTokens: contextTokens, question: question, model: resolvedModel)
    }

    func send(context: String, contextTokens: Int) {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard let apiKey = AISettings.loadAPIKey(for: selectedProvider) else {
            error = .noAPIKey
            return
        }

        let model = resolvedModel
        let totalInput = inputTokenEstimate(for: contextTokens)
        if totalInput > model.contextWindow {
            error = .contextTooLarge(limit: model.contextWindow, actual: totalInput)
            return
        }

        error = nil
        let q = question
        QuestionHistory.record(q)
        questionHistory = QuestionHistory.load()
        question = "" // clear the input so the box is ready for the next turn

        conversation.addUserQuestion(q)
        // Context is re-embedded into the first user message on every send, then
        // the transcript is truncated to the model budget (AC#1–3).
        let wire = conversation.requestMessages(context: context, model: model)
        conversation.beginAssistant()
        isStreaming = true

        streamTask = Task {
            do {
                let stream = await client.ask(messages: wire, model: model, apiKey: apiKey)
                for try await delta in stream {
                    try Task.checkCancellation()
                    conversation.appendDelta(delta)
                }
                conversation.completeAssistant()
            } catch is CancellationError {
                conversation.endInterruptedAssistant()
            } catch let clientError as AIClientError {
                conversation.endInterruptedAssistant()
                error = clientError
            } catch {
                conversation.endInterruptedAssistant()
                self.error = .networkError(underlying: error.localizedDescription)
            }
            isStreaming = false
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        stop()
        conversation.clear()
        error = nil
        question = ""
    }

    /// Copies the whole conversation (as Markdown) to the clipboard.
    func copyConversation() {
        guard hasConversation else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(distilledConversation, forType: .string)
    }

    /// Distills the conversation into a new Markdown note in the vault — the
    /// vault→chat→vault flywheel.
    func saveAsContext(to fm: MDFileManager, collection: String?) {
        guard hasConversation else { return }
        let firstQuestion = conversation.messages.first?.content ?? ""
        let prefix = String(firstQuestion.prefix(Self.responseFilenamePrefixLength))
        let sanitized = FilenameSanitizer.sanitize(prefix)
        let name = sanitized.isEmpty ? "ask-conversation" : "ask-\(sanitized)"
        _ = fm.create(name: name, content: distilledConversation, collection: collection)
    }

    func clearQuestionHistory() {
        QuestionHistory.clear()
        questionHistory = []
    }

    func reloadSettings() {
        selectedProvider = AISettings.loadProvider()
        selectedModelID = AISettings.loadModelID()
        hasAPIKey = AISettings.loadAPIKey(for: selectedProvider) != nil
    }
}
