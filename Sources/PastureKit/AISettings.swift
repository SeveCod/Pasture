import Foundation

public enum AISettings {
    private static let providerKey = "com.sevecod.pasture.aiProvider"
    private static let modelIDKey = "com.sevecod.pasture.aiModelID"
    private static let keychainKeyAnthropic = "anthropic_api_key"
    private static let keychainKeyOpenRouter = "openrouter_api_key"

    public static let didChangeNotification = Notification.Name("PastureAISettingsDidChange")

    public static func loadProvider(from defaults: UserDefaults = .standard) -> AIProviderKind {
        guard let raw = defaults.string(forKey: providerKey),
              let provider = AIProviderKind(rawValue: raw) else { return .anthropic }
        return provider
    }

    public static func saveProvider(_ provider: AIProviderKind, to defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: providerKey)
    }

    public static func loadModelID(from defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: modelIDKey) ?? AIModel.defaultModelID
    }

    public static func saveModelID(_ id: String, to defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: modelIDKey)
    }

    public static func loadAPIKey(for provider: AIProviderKind) -> String? {
        KeychainStore.load(key: keychainKey(for: provider))
    }

    public static func saveAPIKey(_ key: String, for provider: AIProviderKind) throws {
        try KeychainStore.save(key: keychainKey(for: provider), value: key)
    }

    public static func deleteAPIKey(for provider: AIProviderKind) {
        KeychainStore.delete(key: keychainKey(for: provider))
    }

    public static func resolveModel(from defaults: UserDefaults = .standard) -> AIModel {
        let id = loadModelID(from: defaults)
        return AIModel.resolve(id: id)
    }

    private static func keychainKey(for provider: AIProviderKind) -> String {
        switch provider {
        case .anthropic: return keychainKeyAnthropic
        case .openRouter: return keychainKeyOpenRouter
        }
    }
}
