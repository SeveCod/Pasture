import Testing
import Foundation
@testable import PastureKit

@Suite("AISettings")
struct AISettingsTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.sevecod.pasture.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Provider defaults to anthropic")
    func defaultProvider() {
        let defaults = makeIsolatedDefaults()
        #expect(AISettings.loadProvider(from: defaults) == .anthropic)
    }

    @Test("Provider save and load roundtrip")
    func providerRoundtrip() {
        let defaults = makeIsolatedDefaults()
        AISettings.saveProvider(.openRouter, to: defaults)
        #expect(AISettings.loadProvider(from: defaults) == .openRouter)
    }

    @Test("Model ID defaults to defaultModelID")
    func defaultModelID() {
        let defaults = makeIsolatedDefaults()
        #expect(AISettings.loadModelID(from: defaults) == AIModel.defaultModelID)
    }

    @Test("Model ID save and load roundtrip")
    func modelIDRoundtrip() {
        let defaults = makeIsolatedDefaults()
        AISettings.saveModelID("claude-haiku-3-5-20241022", to: defaults)
        #expect(AISettings.loadModelID(from: defaults) == "claude-haiku-3-5-20241022")
    }

    @Test("Resolve model returns valid AIModel")
    func resolveModel() {
        let defaults = makeIsolatedDefaults()
        let model = AISettings.resolveModel(from: defaults)
        #expect(model.id == AIModel.defaultModelID)
        #expect(model.contextWindow > 0)
    }

    @Test("Resolve model falls back for unknown ID")
    func resolveModelFallback() {
        let defaults = makeIsolatedDefaults()
        AISettings.saveModelID("nonexistent-model-xyz", to: defaults)
        let model = AISettings.resolveModel(from: defaults)
        #expect(!model.id.isEmpty)
        #expect(model.contextWindow > 0)
    }

    @Test("Notification name exists")
    func notificationName() {
        #expect(AISettings.didChangeNotification.rawValue == "PastureAISettingsDidChange")
    }

    @Test("Corrupt provider string defaults to anthropic")
    func corruptProviderFallback() {
        let defaults = makeIsolatedDefaults()
        defaults.set("invalid_provider", forKey: "com.sevecod.pasture.aiProvider")
        #expect(AISettings.loadProvider(from: defaults) == .anthropic)
    }

    @Test("Resolve model with non-default model ID")
    func resolveSpecificModel() {
        let defaults = makeIsolatedDefaults()
        AISettings.saveModelID("claude-haiku-3-5-20241022", to: defaults)
        let model = AISettings.resolveModel(from: defaults)
        #expect(model.id == "claude-haiku-3-5-20241022")
        #expect(model.displayName.contains("Haiku"))
    }

    @Test("Provider roundtrip for all cases")
    func allProviderRoundtrips() {
        let defaults = makeIsolatedDefaults()
        for provider in AIProviderKind.allCases {
            AISettings.saveProvider(provider, to: defaults)
            #expect(AISettings.loadProvider(from: defaults) == provider)
        }
    }

    @Test("Model ID persists empty string")
    func emptyModelIDPersists() {
        let defaults = makeIsolatedDefaults()
        AISettings.saveModelID("", to: defaults)
        #expect(AISettings.loadModelID(from: defaults) == "")
    }
}
