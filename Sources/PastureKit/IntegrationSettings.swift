import Foundation

/// v1.9 — Preferencias de integración con el sistema (hotkeys globales,
/// icono del Dock, preset por defecto para el feed headless).
/// Mismo patrón que ExportSettings/AISettings: namespace estático sobre
/// UserDefaults con defaults inyectables para tests.
public enum IntegrationSettings {

    static let hideDockIconKey = "pastureHideDockIcon"
    static let globalHotkeysEnabledKey = "pastureGlobalHotkeysEnabled"
    static let defaultPresetIDKey = "pastureDefaultPresetID"

    public static let didChangeNotification = Notification.Name("PastureIntegrationSettingsDidChange")

    public static func hideDockIcon(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hideDockIconKey)
    }

    public static func setHideDockIcon(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: hideDockIconKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Default false: los hotkeys globales son opt-in — nunca sorprender
    /// con capturas de teclado a nivel de sistema.
    public static func globalHotkeysEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: globalHotkeysEnabledKey)
    }

    public static func setGlobalHotkeysEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: globalHotkeysEnabledKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func defaultPresetID(from defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: defaultPresetIDKey).flatMap(UUID.init(uuidString:))
    }

    public static func setDefaultPresetID(_ id: UUID?, in defaults: UserDefaults = .standard) {
        if let id {
            defaults.set(id.uuidString, forKey: defaultPresetIDKey)
        } else {
            defaults.removeObject(forKey: defaultPresetIDKey)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
