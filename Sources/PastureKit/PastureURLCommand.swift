import Foundation

/// v1.9 — Comandos del URL scheme `pasture://`. Parser puro y testable;
/// el dispatch (AppKit) vive en AppDelegate. Un URL no reconocido devuelve
/// nil y se ignora en silencio — nunca crashea ni ejecuta nada.
public enum PastureURLCommand: Equatable, Sendable {
    /// pasture://feed[?preset=Nombre] — feed headless al portapapeles.
    case feed(presetName: String?)
    /// pasture://new[?title=T][&text=B] — captura una nota nueva.
    case new(title: String?, text: String?)
    /// pasture://search?q=término — abre la ventana con la búsqueda aplicada.
    case search(query: String)

    public static func parse(_ url: URL) -> PastureURLCommand? {
        guard url.scheme?.lowercased() == "pasture",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        switch components.host?.lowercased() {
        case "feed":
            return .feed(presetName: value("preset"))
        case "new":
            return .new(title: value("title"), text: value("text"))
        case "search":
            guard let query = value("q") else { return nil }
            return .search(query: query)
        default:
            return nil
        }
    }
}
