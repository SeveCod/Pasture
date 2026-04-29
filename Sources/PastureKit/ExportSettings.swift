import Foundation

public enum ExportSettings {
    private static let destinationsKey = "com.sevecod.pasture.exportDestinations"
    private static let defaultIDKey = "com.sevecod.pasture.defaultDestinationID"

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
}
