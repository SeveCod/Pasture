import Foundation

/// v1.9 — Propuesta pura de nota para la captura rápida (hotkey global,
/// menú Servicios y pasture://new). Decide nombre base y contenido; el I/O
/// (dedupe + escritura en disco) vive en la app (HeadlessActions).
///
/// La colección destino es `Captures/` — visible, distinta del `.inbox/`
/// oculto del Memory Inbox (propuestas MCP, v1.8).
public enum QuickCapture {

    public static let collectionName = "Captures"
    public static let maxBaseNameLength = 40

    public struct Proposal: Equatable, Sendable {
        public let baseName: String   // sin extensión .md
        public let content: String
    }

    /// `nil` si el texto está vacío o es solo whitespace. El nombre sale del
    /// título explícito o de la primera línea no vacía; si tras sanear no
    /// queda nada, timestamp determinista (clock inyectado, patrón Freshness).
    public static func proposal(text: String, title: String? = nil, now: Date = Date()) -> Proposal? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = (trimmedTitle?.isEmpty == false ? trimmedTitle! : nil)
            ?? body.components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces)
            ?? ""

        var base = FilenameSanitizer.sanitize(String(candidate.prefix(maxBaseNameLength)))
        if base.isEmpty {
            base = "capture-" + timestamp(now)
        }
        return Proposal(baseName: base, content: body + "\n")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
