import Foundation

/// Qué colecciones del sidebar están desplegadas. Mismo patrón que
/// `SelectionPresetStore`: namespace estático, `UserDefaults` inyectable.
///
/// La clave es el `id` de `CollectionNode`, no el nombre: así la raíz
/// (*Uncategorized*) tiene entrada propia.
public enum CollectionExpansionStore {
    private static let key = "com.sevecod.pasture.expandedCollections"

    public static func load(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public static func save(_ expanded: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(Array(expanded), forKey: key)
    }

    /// Si una colección se ve abierta ahora mismo. Con búsqueda activa se abre
    /// todo, para que ninguna coincidencia quede escondida tras un triángulo.
    public static func effectiveExpansion(
        stored: Set<String>, nodeID: String, isSearching: Bool
    ) -> Bool {
        isSearching || stored.contains(nodeID)
    }

    /// Nuevo estado tras plegar o desplegar. Durante una búsqueda **no se escribe
    /// nada**: al borrar la búsqueda, el sidebar vuelve al pliegue que tenía.
    public static func applying(
        _ expanded: Bool, to stored: Set<String>, nodeID: String, isSearching: Bool
    ) -> Set<String> {
        guard !isSearching else { return stored }
        var next = stored
        if expanded { next.insert(nodeID) } else { next.remove(nodeID) }
        return next
    }
}
