import Foundation

/// F2 — Un preset de selección: nombre + lista de paths RELATIVOS a `~/.pasture/`.
///
/// SEC-7: NUNCA persiste contenido de fichero, URLs absolutas ni nada sensible.
/// Un preset es una *referencia*, no una fuente de verdad (ADR-003).
public struct SelectionPreset: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// Paths relativos a `~/.pasture/` (ej: "notes.md", "proyectoX/spec.md").
    public var relativePaths: [String]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, relativePaths: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.relativePaths = relativePaths
        self.createdAt = createdAt
    }

    // MARK: — SEC-8: validación del nombre

    /// Longitud máxima del nombre de preset.
    public static let maxNameLength = 80

    /// Normaliza un nombre de preset: elimina caracteres de control (incluidos
    /// saltos de línea y `\0`), recorta espacios y limita la longitud. Devuelve
    /// cadena vacía si tras sanear no queda nada (el llamante lo rechaza).
    public static func sanitizedName(_ raw: String) -> String {
        let withoutControl = raw.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(Character.init)
        let trimmed = String(withoutControl).trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix(maxNameLength))
    }

    // MARK: — M-3: mensaje accionable de ficheros ausentes

    /// Texto para el toast cuando un preset referencia ficheros que ya no están.
    /// Nombra el primero y cuenta el resto. `nil` si no falta ninguno.
    public static func missingFilesMessage(missingPaths: [String]) -> String? {
        guard let first = missingPaths.first else { return nil }
        let rest = missingPaths.count - 1
        if rest == 0 {
            return "'\(first)' not found"
        }
        return "'\(first)' and \(rest) more not found"
    }
}
