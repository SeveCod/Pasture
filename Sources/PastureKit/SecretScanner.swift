import Foundation

/// Familia de secreto detectada. Driver del texto que ve el usuario en el aviso.
public enum SecretKind: String, Sendable, CaseIterable, Hashable {
    case anthropicKey   // sk-ant-...
    case openAIKey      // sk-... / sk-proj-... (genérico, excluyendo sk-ant)
    case githubToken    // ghp_ / gho_ / ghu_ / ghs_ / github_pat_ (fine-grained)
    case awsAccessKey   // AKIA / ASIA (STS temporal) [0-9A-Z]{16}
    case pemPrivateKey  // -----BEGIN ... PRIVATE KEY-----
    case slackToken     // xox[baprs]-...

    /// Etiqueta legible para el aviso. No expone ningún valor.
    public var displayName: String {
        switch self {
        case .anthropicKey: return "Anthropic key"
        case .openAIKey: return "OpenAI-style key"
        case .githubToken: return "GitHub token"
        case .awsAccessKey: return "AWS access key"
        case .pemPrivateKey: return "PEM private key"
        case .slackToken: return "Slack token"
        }
    }
}

/// Una coincidencia concreta dentro de un fichero.
///
/// SEC-4: NUNCA contiene el valor del secreto completo. Solo tipo, fichero,
/// línea y un fragmento enmascarado para mostrar sin re-exponer la credencial.
public struct SecretMatch: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: SecretKind
    public let fileName: String
    public let lineNumber: Int          // 1-based
    public let maskedSnippet: String    // p.ej. "sk-ant-…SECRET" — nunca el valor completo

    public init(id: UUID = UUID(), kind: SecretKind, fileName: String, lineNumber: Int, maskedSnippet: String) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.lineNumber = lineNumber
        self.maskedSnippet = maskedSnippet
    }
}

/// Resultado agregado de un escaneo. Vacío => no hay fricción (caso limpio).
public struct SecretScanResult: Sendable, Hashable {
    public let matches: [SecretMatch]

    public init(matches: [SecretMatch]) {
        self.matches = matches
    }

    public var isEmpty: Bool { matches.isEmpty }

    /// Tipos únicos detectados (para el resumen "Anthropic key, GitHub token").
    public var kinds: Set<SecretKind> { Set(matches.map(\.kind)) }

    /// Agrupación para el diálogo: por fichero, luego por tipo.
    public func grouped() -> [String: [SecretKind: [SecretMatch]]] {
        var result: [String: [SecretKind: [SecretMatch]]] = [:]
        for match in matches {
            result[match.fileName, default: [:]][match.kind, default: []].append(match)
        }
        return result
    }

    /// Líneas legibles para el diálogo de aviso, agrupadas por fichero y tipo.
    /// SEC-4: NUNCA incluye el valor del secreto, solo fichero + familia (+ conteo).
    public func summaryLines() -> [String] {
        let grouped = grouped()
        var lines: [String] = []
        for fileName in grouped.keys.sorted() {
            guard let kindsMap = grouped[fileName] else { continue }
            let kindParts = kindsMap.keys
                .sorted { $0.displayName < $1.displayName }
                .map { kind -> String in
                    let count = kindsMap[kind]?.count ?? 0
                    return count > 1 ? "\(kind.displayName) (\u{00d7}\(count))" : kind.displayName
                }
            lines.append("\(fileName): \(kindParts.joined(separator: ", "))")
        }
        return lines
    }
}

/// Detector best-effort de credenciales en el contenido del feed.
///
/// Determinista, sin estado, `nonisolated`: pensado para correr fuera del main
/// actor en selecciones grandes. NO decide políticas de UI (avisar/bloquear);
/// solo detecta y reporta. La política vive en la capa de UI.
///
/// Limitaciones (SEC-5): es una red de seguridad, NO una garantía. El catálogo
/// cubre las familias más comunes del flujo dev, no todo secreto posible.
public enum SecretScanner {

    /// Límite de tamaño de escaneo por fichero (SEC-3). Protege contra inputs
    /// gigantes a coste de no cubrir la cola de ficheros enormes.
    public static let maxScanBytes = 2_000_000  // ~2 MB por fichero

    public struct Input: Sendable {
        public let fileName: String
        public let content: String

        public init(fileName: String, content: String) {
            self.fileName = fileName
            self.content = content
        }
    }

    /// Patrón anclado por familia. El orden importa: Anthropic se evalúa antes
    /// que el genérico `sk-` para no misclasificar (SEC-2).
    private struct Pattern {
        let kind: SecretKind
        let regex: NSRegularExpression
    }

    /// Catálogo precompilado UNA sola vez (ADR-001). Patrones lineales/anclados,
    /// sin cuantificadores anidados que permitan backtracking catastrófico (SEC-3).
    private static let patterns: [Pattern] = {
        func compile(_ source: String) -> NSRegularExpression {
            // Patrones del catálogo son estáticos y válidos; un fallo aquí es un bug.
            try! NSRegularExpression(pattern: source, options: [])
        }
        return [
            // Anthropic: literal sk-ant- + cuerpo alfanumérico/guiones. ANTES que openAI.
            Pattern(kind: .anthropicKey, regex: compile("sk-ant-[A-Za-z0-9_-]{20,}")),
            // GitHub clásico: la clase [opus] hace coincidir la 3ª letra del prefijo,
            // cubriendo ghp_ (personal), gho_ (oauth), ghu_ (user-to-server) y
            // ghs_ (server-to-server) en un solo patrón. + >=20 alfanuméricos.
            Pattern(kind: .githubToken, regex: compile("gh[opus]_[A-Za-z0-9]{20,}")),
            // GitHub fine-grained (recomendado desde 2023): github_pat_ + cuerpo con
            // alfanuméricos y guiones bajos. El patrón clásico gh[opus]_ no lo cubre.
            Pattern(kind: .githubToken, regex: compile("github_pat_[A-Za-z0-9_]{20,}")),
            // AWS access key: AKIA (largo plazo) o ASIA (STS temporal) + 16
            // mayúsculas/dígitos, con límite de palabra.
            Pattern(kind: .awsAccessKey, regex: compile("\\bA[SK]IA[0-9A-Z]{16}\\b")),
            // Slack: xox[baprs]- + cuerpo.
            Pattern(kind: .slackToken, regex: compile("xox[baprs]-[A-Za-z0-9-]{10,}")),
            // PEM: basta la cabecera BEGIN ... PRIVATE KEY-----.
            Pattern(kind: .pemPrivateKey, regex: compile("-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")),
            // OpenAI project (por defecto desde 2024): sk-proj- + cuerpo con guiones
            // y guiones bajos. El genérico sk- no lo cubre (el '-' tras 'proj' lo corta).
            Pattern(kind: .openAIKey, regex: compile("sk-proj-[A-Za-z0-9_-]{20,}")),
            // OpenAI genérico: sk- + >=20 alfanuméricos. Negar el prefijo sk-ant- por orden
            // (se filtra abajo: un match openAI cuyo texto empieza por "sk-ant-" se descarta).
            Pattern(kind: .openAIKey, regex: compile("sk-[A-Za-z0-9]{20,}")),
        ]
    }()

    /// Escaneo síncrono puro. Determinista, sin estado.
    public static func scan(_ inputs: [Input]) -> SecretScanResult {
        var matches: [SecretMatch] = []
        for input in inputs {
            matches.append(contentsOf: scanContent(fileName: input.fileName, content: input.content))
        }
        return SecretScanResult(matches: matches)
    }

    /// Conveniencia para un solo fichero.
    public static func scan(fileName: String, content: String) -> SecretScanResult {
        scan([Input(fileName: fileName, content: content)])
    }

    // MARK: — Escaneo por fichero

    private static func scanContent(fileName: String, content: String) -> [SecretMatch] {
        // SEC-3: limitar el tamaño escaneado por fichero.
        let scanned = cappedContent(content)
        var matches: [SecretMatch] = []

        // Escaneo línea a línea: acota el coste por regex y da el número de línea.
        var lineNumber = 0
        scanned.enumerateLines { line, _ in
            lineNumber += 1
            for pattern in patterns {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                pattern.regex.enumerateMatches(in: line, options: [], range: range) { result, _, _ in
                    guard let result, let r = Range(result.range, in: line) else { return }
                    let matchedText = String(line[r])
                    // SEC-2: un match del genérico sk- que en realidad es sk-ant- ya
                    // fue capturado por la familia Anthropic; lo descartamos aquí.
                    if pattern.kind == .openAIKey, matchedText.hasPrefix("sk-ant-") { return }
                    matches.append(
                        SecretMatch(
                            kind: pattern.kind,
                            fileName: fileName,
                            lineNumber: lineNumber,
                            maskedSnippet: mask(matchedText)
                        )
                    )
                }
            }
        }

        // PEM puede ser multilínea; la cabecera BEGIN cae en una sola línea, así que
        // enumerateLines ya la cubre. No se requiere pase multilínea adicional.
        return matches
    }

    /// Recorta el contenido al cap de tamaño SIN partir un carácter UTF-8
    /// multibyte (I-1). Busca la frontera de carácter más cercana por debajo del
    /// límite de bytes, de modo que el resultado nunca contiene U+FFFD por un
    /// carácter truncado a media codificación.
    static func cappedContent(_ content: String) -> String {
        guard content.utf8.count > maxScanBytes else { return content }
        let utf8 = content.utf8
        guard let byteLimit = utf8.index(utf8.startIndex, offsetBy: maxScanBytes, limitedBy: utf8.endIndex)
        else { return content }
        // Retrocede hasta una frontera de carácter válida (no a mitad de un escalar).
        var boundary = byteLimit
        while boundary > utf8.startIndex, boundary.samePosition(in: content) == nil {
            boundary = utf8.index(before: boundary)
        }
        let stringIndex = boundary.samePosition(in: content) ?? content.startIndex
        return String(content[content.startIndex..<stringIndex])
    }

    // MARK: — SEC-4: enmascarado (nunca el valor completo)

    /// Muestra los primeros 7 + `…` + los últimos 4 caracteres. Para secretos
    /// cortos, enmascara aún más agresivamente para no exponer el grueso del valor.
    static func mask(_ secret: String) -> String {
        let head = 7
        let tail = 4
        guard secret.count > head + tail else {
            // Demasiado corto para revelar nada: solo el primer carácter + marca.
            return "\(secret.prefix(1))\u{2026}"
        }
        let prefix = secret.prefix(head)
        let suffix = secret.suffix(tail)
        return "\(prefix)\u{2026}\(suffix)"
    }
}
