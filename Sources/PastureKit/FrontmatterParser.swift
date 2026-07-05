import Foundation

/// Metadatos de frescura/procedencia de una nota, extraídos de un bloque
/// frontmatter YAML-lite al principio del fichero. Todos opcionales: una nota sin
/// frontmatter (o con frontmatter inválido) simplemente no tiene metadatos y se
/// considera fresca (nunca caduca).
public struct Frontmatter: Sendable, Equatable {
    /// Fecha absoluta tras la cual la nota deja de ser fiable (`review_after`).
    public let reviewAfter: Date?
    /// Vida útil en días desde `last_reviewed` (o la fecha de modificación) (`ttl`).
    public let ttlDays: Int?
    /// Fecha de la última revisión manual (`last_reviewed`).
    public let lastReviewed: Date?
    /// Carpeta local de origen para re-importación (`source`) — reservado para Fase B.
    public let source: String?
    /// Marca de nota generada por una fuente/agente (`generated`).
    public let generated: Bool

    public init(
        reviewAfter: Date? = nil, ttlDays: Int? = nil, lastReviewed: Date? = nil,
        source: String? = nil, generated: Bool = false
    ) {
        self.reviewAfter = reviewAfter
        self.ttlDays = ttlDays
        self.lastReviewed = lastReviewed
        self.source = source
        self.generated = generated
    }

    /// ¿Declara la nota alguna caducidad? Si no, `Freshness` la trata como fresca.
    public var declaresExpiry: Bool { reviewAfter != nil || ttlDays != nil }
}

/// Parser hand-rolled de un subconjunto `clave: valor` de YAML (SEC-M10: sin
/// dependencia YAML). Tolerante por diseño (anti-DoS, SEC-M12): un frontmatter
/// hostil o malformado jamás lanza — degrada a 'sin metadatos'. Sin regex con
/// cuantificadores anidados (escaneo por líneas).
public enum FrontmatterParser {

    /// Cap de tamaño del bloque frontmatter (SEC): más allá, no se parsea.
    public static let maxBlockBytes = 8_192          // 8 KB
    public static let maxBlockLines = 64

    /// Claves reconocidas en v1 (otras se ignoran en silencio).
    public static let recognizedKeys: Set<String> = ["review_after", "ttl", "last_reviewed", "source", "generated"]

    public struct ParseResult: Sendable, Equatable {
        /// `nil` si no hay bloque frontmatter válido.
        public let frontmatter: Frontmatter?
        /// Contenido SIN el bloque frontmatter (igual al original si no había).
        public let body: String
    }

    /// Extrae el frontmatter (si existe) y devuelve el cuerpo sin el bloque.
    public static func parse(_ content: String) -> ParseResult {
        // El bloque debe empezar EXACTAMENTE con "---" en la primera línea.
        guard content.hasPrefix("---\n") || content.hasPrefix("---\r\n") else {
            return ParseResult(frontmatter: nil, body: content)
        }

        // Separar en líneas preservando el resto. Buscamos el cierre "---".
        let lines = content.components(separatedBy: "\n")
        // lines[0] == "---" (o "---\r"). Buscar el cierre entre las siguientes.
        var closingIndex: Int?
        var scanned = 0
        var scannedBytes = 0
        for i in 1..<lines.count {
            let raw = lines[i]
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            scanned += 1
            scannedBytes += raw.utf8.count + 1
            // Anti-DoS: si el bloque excede los caps sin cerrar, se abandona.
            if scanned > maxBlockLines || scannedBytes > maxBlockBytes { break }
            if line == "---" {
                closingIndex = i
                break
            }
        }

        guard let closing = closingIndex else {
            // Delimitador sin cerrar (o excede caps) → tratamos como sin frontmatter.
            return ParseResult(frontmatter: nil, body: content)
        }

        // Parsear las líneas del bloque (entre la 1 y el cierre).
        var pairs: [String: String] = [:]
        for i in 1..<closing {
            let raw = lines[i]
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard recognizedKeys.contains(key) else { continue }
            // Clave duplicada: gana la primera (determinista).
            if pairs[key] == nil { pairs[key] = value }
        }

        let frontmatter = Frontmatter(
            reviewAfter: pairs["review_after"].flatMap(parseDate),
            ttlDays: pairs["ttl"].flatMap(parseTTLDays),
            lastReviewed: pairs["last_reviewed"].flatMap(parseDate),
            source: pairs["source"].flatMap { $0.isEmpty ? nil : $0 },
            generated: parseBool(pairs["generated"]))

        // El cuerpo es todo lo que sigue a la línea de cierre.
        let bodyLines = lines[(closing + 1)...]
        let body = bodyLines.joined(separator: "\n")
        return ParseResult(frontmatter: frontmatter, body: body)
    }

    // MARK: — Parseo de valores tipados (tolerante: valor basura → nil)

    /// Fecha ISO `yyyy-MM-dd` a medianoche UTC. Valor inválido → nil.
    static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    /// `ttl` en días. Acepta "90" o "90d". Valor inválido/negativo → nil.
    static func parseTTLDays(_ value: String) -> Int? {
        var digits = value
        if digits.hasSuffix("d") || digits.hasSuffix("D") { digits.removeLast() }
        digits = digits.trimmingCharacters(in: .whitespaces)
        guard let days = Int(digits), days > 0 else { return nil }
        return days
    }

    static func parseBool(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value == "true" || value == "yes" || value == "1"
    }
}
