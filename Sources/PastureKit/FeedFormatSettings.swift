import Foundation

/// Persistencia del formato de salida del feed (XML / Markdown / plano).
/// Mismo patrón que ExportSettings/AISettings: namespace estático + UserDefaults
/// + notificación. Clave propia, ortogonal a ExportSettings (ADR-005).
public enum FeedFormatSettings {
    private static let feedFormatKey = "com.sevecod.pasture.feedFormat"

    public static let didChangeNotification = Notification.Name("PastureFeedFormatSettingsDidChange")

    public static func feedFormat(from defaults: UserDefaults = .standard) -> FeedFormat {
        guard let raw = defaults.string(forKey: feedFormatKey),
              let format = FeedFormat(rawValue: raw)
        else { return .xml }
        return format
    }

    public static func setFeedFormat(_ format: FeedFormat, in defaults: UserDefaults = .standard) {
        defaults.set(format.rawValue, forKey: feedFormatKey)
    }
}
