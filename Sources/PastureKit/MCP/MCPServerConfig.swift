import Foundation

/// Configuración del servidor MCP (ADR-007).
///
/// El proceso `pasture-mcp` NO comparte el dominio de `UserDefaults` de la app
/// GUI: leer `FeedFormatSettings` desde aquí devolvería siempre el default. Por
/// eso la configuración se resuelve del entorno, con el mismo default `.xml`.
public struct MCPServerConfig: Sendable {
    /// Raíz del vault. Fija a `~/.pasture/` en producción; inyectable en tests.
    public let vaultRoot: URL
    /// Formato del feed para `feed_context`. Default `.xml` (igual que la app).
    public let feedFormat: FeedFormat
    /// v1.8: si es `true`, el catálogo expone las tools de propuesta (write-path
    /// al `.inbox/`). Default `false` = regresión de solo-lectura idéntica a v1.7.
    public let allowProposals: Bool

    public init(vaultRoot: URL, feedFormat: FeedFormat, allowProposals: Bool = false) {
        self.vaultRoot = vaultRoot
        self.feedFormat = feedFormat
        self.allowProposals = allowProposals
    }

    /// Variable de entorno que el cliente MCP puede inyectar en su config para
    /// fijar el formato del feed. Ausente o inválida ⇒ default `.xml`.
    public static let feedFormatEnvKey = "PASTURE_FEED_FORMAT"

    /// Variable de entorno que habilita el camino de propuestas. Solo el valor
    /// exacto `"1"` lo activa; cualquier otra cosa (o ausente) ⇒ `false`.
    public static let allowProposalsEnvKey = "PASTURE_ALLOW_PROPOSALS"

    /// Construye la configuración desde el entorno del proceso.
    /// - Vault: `~/.pasture/` (raíz única, ADR-003).
    /// - Formato: `PASTURE_FEED_FORMAT` (`xml`/`markdown`/`plainText`), default `.xml`.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> MCPServerConfig {
        let vault = homeDirectory.appendingPathComponent(".pasture", isDirectory: true)
        let format = environment[feedFormatEnvKey]
            .flatMap { FeedFormat(rawValue: $0) } ?? .xml
        let allowProposals = environment[allowProposalsEnvKey] == "1"
        return MCPServerConfig(vaultRoot: vault, feedFormat: format, allowProposals: allowProposals)
    }
}
