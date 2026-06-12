import Foundation

/// Extensión de archivo usada al exportar feed context a disco.
public enum ExportFileFormat: String, Codable, CaseIterable, Sendable {
    case markdown = "md"
    case plainText = "txt"

    public var fileExtension: String { rawValue }

    public var displayName: String {
        switch self {
        case .markdown: return "Markdown (.md)"
        case .plainText: return "Plain text (.txt)"
        }
    }
}

public enum ExportSettings {
    private static let destinationsKey = "com.sevecod.pasture.exportDestinations"
    private static let defaultIDKey = "com.sevecod.pasture.defaultDestinationID"
    private static let fileFormatKey = "com.sevecod.pasture.exportFileFormat"

    public static let didChangeNotification = Notification.Name("PastureExportSettingsDidChange")

    public static func loadDestinations(from defaults: UserDefaults = .standard) -> [ExportDestination] {
        guard let data = defaults.data(forKey: destinationsKey),
              let destinations = try? JSONDecoder().decode([ExportDestination].self, from: data)
        else { return [] }
        return destinations
    }

    public static func saveDestinations(_ destinations: [ExportDestination], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(destinations) else { return }
        defaults.set(data, forKey: destinationsKey)
    }

    public static func defaultDestinationID(from defaults: UserDefaults = .standard) -> UUID? {
        guard let str = defaults.string(forKey: defaultIDKey) else { return nil }
        return UUID(uuidString: str)
    }

    public static func setDefaultDestinationID(_ id: UUID?, in defaults: UserDefaults = .standard) {
        defaults.set(id?.uuidString, forKey: defaultIDKey)
    }

    public static func fileFormat(from defaults: UserDefaults = .standard) -> ExportFileFormat {
        guard let raw = defaults.string(forKey: fileFormatKey),
              let format = ExportFileFormat(rawValue: raw)
        else { return .markdown }
        return format
    }

    public static func setFileFormat(_ format: ExportFileFormat, in defaults: UserDefaults = .standard) {
        defaults.set(format.rawValue, forKey: fileFormatKey)
    }
}
