import SwiftUI
import AppKit
import PastureKit

@MainActor
final class AskViewModel: ObservableObject {
    @Published var question = ""
    @Published var responseText = ""
    @Published var isStreaming = false
    @Published var error: AIClientError?
    @Published private(set) var selectedProvider: AIProviderKind = AISettings.loadProvider()
    @Published private(set) var selectedModelID: String = AISettings.loadModelID()
    @Published private(set) var hasAPIKey: Bool = false

    static let responseFilenamePrefixLength = 40

    private let client = AIClient()
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
        responseText = ""
        isStreaming = true

        let q = question

        streamTask = Task {
            do {
                let stream = await client.ask(question: q, context: context, model: model, apiKey: apiKey)
                for try await delta in stream {
                    responseText += delta
                }
            } catch let clientError as AIClientError {
                error = clientError
            } catch {
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
        responseText = ""
        error = nil
        question = ""
    }

    func copyResponse() {
        guard !responseText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText, forType: .string)
    }

    func saveResponse(to fm: MDFileManager, collection: String?) {
        guard !responseText.isEmpty else { return }
        let prefix = String(question.prefix(Self.responseFilenamePrefixLength))
        let sanitized = FilenameSanitizer.sanitize(prefix)
        let name = sanitized.isEmpty ? "ask-response" : "ask-\(sanitized)"
        _ = fm.create(name: name, content: responseText, collection: collection)
    }

    func reloadSettings() {
        selectedProvider = AISettings.loadProvider()
        selectedModelID = AISettings.loadModelID()
        hasAPIKey = AISettings.loadAPIKey(for: selectedProvider) != nil
    }
}
