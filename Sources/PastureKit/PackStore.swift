import Foundation

/// Context Compiler (v1.6) — persistencia CRUD de packs de compilación.
///
/// Mismo patrón que `SelectionPresetStore`: namespace estático + UserDefaults +
/// notificación. Los packs viven en su PROPIA clave, separada de los presets, así
/// que añadir el Context Compiler NO cambia el schema de `SelectionPreset` y los
/// presets v1.4/v1.5 decodifican sin pérdida (AC#7).
public enum PackStore {
    private static let packsKey = "com.sevecod.pasture.compilePacks"

    public static let didChangeNotification = Notification.Name("PastureCompilePacksDidChange")

    /// Caps (mismo espíritu que `SelectionPresetStore.maxPresets`).
    public static let maxPacks = 50
    public static let maxTargetsPerPack = 20

    public static func load(from defaults: UserDefaults = .standard) -> [CompilePack] {
        guard let data = defaults.data(forKey: packsKey),
              let packs = try? JSONDecoder().decode([CompilePack].self, from: data)
        else { return [] }
        return packs
    }

    /// Guarda aplicando los caps: máx. 50 packs, máx. 20 targets por pack.
    public static func save(_ packs: [CompilePack], to defaults: UserDefaults = .standard) {
        let capped = packs.prefix(maxPacks).map { pack -> CompilePack in
            var trimmed = pack
            trimmed.targets = Array(pack.targets.prefix(maxTargetsPerPack))
            return trimmed
        }
        guard let data = try? JSONEncoder().encode(capped) else { return }
        defaults.set(data, forKey: packsKey)
    }

    public static func upsert(_ pack: CompilePack, in defaults: UserDefaults = .standard) {
        var packs = load(from: defaults)
        if let idx = packs.firstIndex(where: { $0.id == pack.id }) {
            packs[idx] = pack
        } else {
            packs.append(pack)
        }
        save(packs, to: defaults)
        post()
    }

    public static func delete(id: UUID, in defaults: UserDefaults = .standard) {
        var packs = load(from: defaults)
        packs.removeAll { $0.id == id }
        save(packs, to: defaults)
        post()
    }

    private static func post() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
