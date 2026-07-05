import Foundation

/// Memoria viva (v1.7, Fase A) — escritura mínima de frontmatter para "marcar
/// revisado". Transformación PURA de string (testeable byte a byte); el I/O a
/// disco vive en la GUI/MDFileManager. Preserva el cuerpo intacto.
public enum FrontmatterWriter {

    /// Devuelve el contenido con `last_reviewed: <yyyy-MM-dd>` fijado. Si ya había
    /// un bloque frontmatter, actualiza/inserta la clave conservando el resto; si
    /// no, antepone un bloque nuevo. El cuerpo no se toca.
    public static func settingLastReviewed(in content: String, to date: Date) -> String {
        let iso = isoString(date)
        let parsed = FrontmatterParser.parse(content)

        // Sin bloque válido → anteponer uno nuevo.
        guard parsed.frontmatter != nil, var lines = extractBlockLines(content) else {
            return "---\nlast_reviewed: \(iso)\n---\n" + content
        }

        if let idx = lines.firstIndex(where: { keyOf($0) == "last_reviewed" }) {
            lines[idx] = "last_reviewed: \(iso)"
        } else {
            lines.append("last_reviewed: \(iso)")
        }
        let newBlock = "---\n" + lines.joined(separator: "\n") + "\n---\n"
        return newBlock + parsed.body
    }

    // MARK: — Helpers internos

    static func isoString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func keyOf(_ line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        return String(line[..<colon]).trimmingCharacters(in: .whitespaces)
    }

    /// Extrae las líneas internas del bloque frontmatter (sin los delimitadores).
    /// Devuelve `nil` si no hay un bloque válido. Reusa la misma detección que el parser.
    static func extractBlockLines(_ content: String) -> [String]? {
        guard content.hasPrefix("---\n") || content.hasPrefix("---\r\n") else { return nil }
        let lines = content.components(separatedBy: "\n")
        for i in 1..<lines.count {
            let raw = lines[i]
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if line == "---" {
                return lines[1..<i].map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
            }
        }
        return nil
    }
}
