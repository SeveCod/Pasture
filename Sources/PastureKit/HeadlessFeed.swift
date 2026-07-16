import Foundation

/// v1.9 — Ensamblado puro del feed headless (hotkey global / pasture://feed).
/// Resuelve el preset, lee los ficheros, escanea secretos y construye el
/// contexto. Sin UI: el llamante decide portapapeles/notificación.
///
/// Política de secretos: BLOQUEA. En la GUI el diálogo tiene Cancel como
/// default; sin diálogo posible, el equivalente conservador es no entregar.
public enum HeadlessFeed {

    public struct Success: Equatable, Sendable {
        public let context: String
        public let fileCount: Int
        public let tokens: Int
        public let missingPaths: [String]
    }

    public enum Outcome: Equatable, Sendable {
        case success(Success)
        case noFiles(missingPaths: [String])
        case secretsDetected(summaryLines: [String])
    }

    public static func build(preset: SelectionPreset, base: URL, format: FeedFormat) -> Outcome {
        let resolution = PresetResolver.resolve(relativePaths: preset.relativePaths, base: base)

        var entries: [ContextBuilder.FileEntry] = []
        var existing: Set<URL> = []
        for url in resolution.urls {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            existing.insert(url)
            entries.append(.init(name: url.lastPathComponent, content: content))
        }
        let missing = PresetResolver.missingPaths(
            relativePaths: preset.relativePaths, base: base, existing: existing
        )

        guard !entries.isEmpty else { return .noFiles(missingPaths: missing) }

        let scan = SecretScanner.scan(entries.map { .init(fileName: $0.name, content: $0.content) })
        guard scan.isEmpty else { return .secretsDetected(summaryLines: scan.summaryLines()) }

        let context = ContextBuilder.build(files: entries, format: format)
        let tokens = entries.reduce(0) { $0 + TokenEstimator.estimate($1.content) }
        return .success(.init(context: context, fileCount: entries.count, tokens: tokens, missingPaths: missing))
    }
}
