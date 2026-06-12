import Foundation

/// F2 — Persistencia CRUD de presets de selección.
/// Mismo patrón que ExportSettings/AISettings: namespace estático + UserDefaults
/// + notificación. SEC-7: solo nombre + rutas relativas. SEC-8: límite de cantidad.
public enum SelectionPresetStore {
    private static let presetsKey = "com.sevecod.pasture.selectionPresets"

    public static let didChangeNotification = Notification.Name("PastureSelectionPresetsDidChange")

    /// Número máximo de presets para no inflar el plist (SEC-8).
    public static let maxPresets = 100

    public static func load(from defaults: UserDefaults = .standard) -> [SelectionPreset] {
        guard let data = defaults.data(forKey: presetsKey),
              let presets = try? JSONDecoder().decode([SelectionPreset].self, from: data)
        else { return [] }
        return presets
    }

    public static func save(_ presets: [SelectionPreset], to defaults: UserDefaults = .standard) {
        let capped = Array(presets.prefix(maxPresets))
        guard let data = try? JSONEncoder().encode(capped) else { return }
        defaults.set(data, forKey: presetsKey)
    }

    /// Inserta o sustituye por id. Dispara `didChangeNotification`.
    public static func upsert(_ preset: SelectionPreset, in defaults: UserDefaults = .standard) {
        var presets = load(from: defaults)
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
        save(presets, to: defaults)
        post()
    }

    public static func delete(id: UUID, in defaults: UserDefaults = .standard) {
        var presets = load(from: defaults)
        presets.removeAll { $0.id == id }
        save(presets, to: defaults)
        post()
    }

    public static func rename(id: UUID, to newName: String, in defaults: UserDefaults = .standard) {
        var presets = load(from: defaults)
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = newName
        save(presets, to: defaults)
        post()
    }

    /// Busca por nombre (case-insensitive) para la confirmación de sobrescritura.
    public static func preset(named name: String, in defaults: UserDefaults = .standard) -> SelectionPreset? {
        load(from: defaults).first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    private static func post() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
