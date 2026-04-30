import Testing
import Foundation
@testable import PastureKit

@Suite("AIProvider & AIModel")
struct AIProviderTests {

    @Test("Default models list is not empty")
    func defaultModelsNotEmpty() {
        #expect(!AIModel.defaultModels.isEmpty)
    }

    @Test("Default model ID exists in catalog")
    func defaultModelIDExists() {
        let model = AIModel.model(byID: AIModel.defaultModelID)
        #expect(model != nil)
        #expect(model?.id == AIModel.defaultModelID)
    }

    @Test("Both providers have at least one model")
    func bothProvidersHaveModels() {
        let anthropic = AIModel.models(for: .anthropic)
        let openRouter = AIModel.models(for: .openRouter)
        #expect(!anthropic.isEmpty)
        #expect(!openRouter.isEmpty)
    }

    @Test("All models have positive pricing")
    func positivePricing() {
        for model in AIModel.defaultModels {
            #expect(model.inputCostPer1M > 0, "Model \(model.id) has zero/negative input cost")
            #expect(model.outputCostPer1M > 0, "Model \(model.id) has zero/negative output cost")
            #expect(model.contextWindow > 0, "Model \(model.id) has zero/negative context window")
        }
    }

    @Test("AIProviderKind has all expected cases")
    func providerCases() {
        let cases = AIProviderKind.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.anthropic))
        #expect(cases.contains(.openRouter))
    }

    @Test("Model lookup for nonexistent ID returns nil")
    func modelLookupNil() {
        #expect(AIModel.model(byID: "nonexistent-model") == nil)
    }

    @Test("AIModel Codable roundtrip")
    func codableRoundtrip() throws {
        let original = AIModel(
            id: "test-model", displayName: "Test", provider: .anthropic,
            contextWindow: 100_000, inputCostPer1M: 1.5, outputCostPer1M: 7.5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIModel.self, from: data)
        #expect(decoded == original)
    }

    @Test("AIModel Hashable: equal models hash equal")
    func hashableEqual() {
        let a = AIModel(id: "x", displayName: "X", provider: .anthropic, contextWindow: 1000, inputCostPer1M: 1, outputCostPer1M: 2)
        let b = AIModel(id: "x", displayName: "X", provider: .anthropic, contextWindow: 1000, inputCostPer1M: 1, outputCostPer1M: 2)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("AIModel Hashable: different IDs hash different")
    func hashableDifferent() {
        let a = AIModel(id: "model-a", displayName: "A", provider: .anthropic, contextWindow: 1000, inputCostPer1M: 1, outputCostPer1M: 2)
        let b = AIModel(id: "model-b", displayName: "B", provider: .anthropic, contextWindow: 1000, inputCostPer1M: 1, outputCostPer1M: 2)
        #expect(a != b)
    }

    @Test("Identifiable id matches string id")
    func identifiableID() {
        let model = AIModel(id: "test-123", displayName: "Test", provider: .openRouter, contextWindow: 1000, inputCostPer1M: 1, outputCostPer1M: 2)
        #expect(model.id == "test-123")
    }

    @Test("models(for:) returns only that provider's models")
    func modelsFilteredByProvider() {
        let anthropicModels = AIModel.models(for: .anthropic)
        for model in anthropicModels {
            #expect(model.provider == .anthropic)
        }
        let openRouterModels = AIModel.models(for: .openRouter)
        for model in openRouterModels {
            #expect(model.provider == .openRouter)
        }
    }

    @Test("All models have non-empty displayName")
    func allModelsHaveDisplayName() {
        for model in AIModel.defaultModels {
            #expect(!model.displayName.isEmpty, "Model \(model.id) has empty displayName")
        }
    }

    @Test("AIProviderKind Codable roundtrip")
    func providerKindCodable() throws {
        for provider in AIProviderKind.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(AIProviderKind.self, from: data)
            #expect(decoded == provider)
        }
    }

    @Test("Default model ID points to an Anthropic model")
    func defaultModelIsAnthropic() {
        let model = AIModel.model(byID: AIModel.defaultModelID)
        #expect(model?.provider == .anthropic)
    }

    // MARK: - AIModel.resolve tests

    @Test("resolve with valid ID returns exact model")
    func resolveExactMatch() {
        let model = AIModel.resolve(id: AIModel.defaultModelID)
        #expect(model.id == AIModel.defaultModelID)
    }

    @Test("resolve with invalid ID and preferred provider returns that provider's first model")
    func resolveWithPreferredProvider() {
        let model = AIModel.resolve(id: "nonexistent", preferredProvider: .anthropic)
        #expect(model.provider == .anthropic)
        let first = AIModel.models(for: .anthropic).first
        #expect(model.id == first?.id)
    }

    @Test("resolve with invalid ID and no preference returns first default model")
    func resolveWithNoPreference() {
        let model = AIModel.resolve(id: "nonexistent")
        #expect(model.id == AIModel.defaultModels[0].id)
    }

    @Test("resolve with invalid ID and .openRouter preference returns openRouter model")
    func resolveOpenRouterPreference() {
        let model = AIModel.resolve(id: "nonexistent", preferredProvider: .openRouter)
        #expect(model.provider == .openRouter)
        let first = AIModel.models(for: .openRouter).first
        #expect(model.id == first?.id)
    }

    @Test("resolve always returns a valid model (never crashes)")
    func resolveAlwaysValid() {
        let cases: [(String, AIProviderKind?)] = [
            (AIModel.defaultModelID, nil),
            (AIModel.defaultModelID, .anthropic),
            ("nonexistent", nil),
            ("nonexistent", .anthropic),
            ("nonexistent", .openRouter),
            ("", nil),
            ("", .anthropic),
        ]
        for (id, provider) in cases {
            let model = AIModel.resolve(id: id, preferredProvider: provider)
            #expect(!model.id.isEmpty, "resolve(\(id), \(String(describing: provider))) returned empty id")
            #expect(model.contextWindow > 0)
        }
    }
}
