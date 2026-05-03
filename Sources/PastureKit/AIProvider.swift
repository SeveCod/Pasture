import Foundation

public enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openRouter
}

public struct AIModel: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var provider: AIProviderKind
    public var contextWindow: Int
    public var maxOutputTokens: Int
    public var inputCostPer1M: Double
    public var outputCostPer1M: Double

    public init(
        id: String,
        displayName: String,
        provider: AIProviderKind,
        contextWindow: Int,
        inputCostPer1M: Double,
        outputCostPer1M: Double,
        maxOutputTokens: Int = 8192
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.inputCostPer1M = inputCostPer1M
        self.outputCostPer1M = outputCostPer1M
    }
}

public extension AIModel {
    static let defaultModelID = "claude-sonnet-4-20250514"

    static let defaultModels: [AIModel] = [
        AIModel(
            id: "claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            provider: .anthropic,
            contextWindow: 200_000,
            inputCostPer1M: 3.0,
            outputCostPer1M: 15.0,
            maxOutputTokens: 16384
        ),
        AIModel(
            id: "claude-haiku-3-5-20241022",
            displayName: "Claude 3.5 Haiku",
            provider: .anthropic,
            contextWindow: 200_000,
            inputCostPer1M: 0.80,
            outputCostPer1M: 4.0,
            maxOutputTokens: 8192
        ),
        AIModel(
            id: "anthropic/claude-sonnet-4-20250514",
            displayName: "Claude Sonnet 4",
            provider: .openRouter,
            contextWindow: 200_000,
            inputCostPer1M: 3.0,
            outputCostPer1M: 15.0,
            maxOutputTokens: 16384
        ),
        AIModel(
            id: "anthropic/claude-haiku-3-5-20241022",
            displayName: "Claude 3.5 Haiku",
            provider: .openRouter,
            contextWindow: 200_000,
            inputCostPer1M: 0.80,
            outputCostPer1M: 4.0,
            maxOutputTokens: 8192
        ),
    ]

    static func models(for provider: AIProviderKind) -> [AIModel] {
        defaultModels.filter { $0.provider == provider }
    }

    static func model(byID id: String) -> AIModel? {
        defaultModels.first { $0.id == id }
    }

    /// Resolves a model by ID with fallback chain: exact match -> preferred provider's first model -> first default model.
    static func resolve(id: String, preferredProvider: AIProviderKind? = nil) -> AIModel {
        if let exact = model(byID: id) { return exact }
        if let provider = preferredProvider,
           let match = defaultModels.first(where: { $0.provider == provider }) {
            return match
        }
        return defaultModels[0]
    }
}
