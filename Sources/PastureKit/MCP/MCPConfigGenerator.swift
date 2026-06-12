import Foundation

/// Generador de configuración para registrar `pasture-mcp` en clientes MCP
/// (HU-2/3). Lógica pura, testeable sin UI. El descubrimiento de la ruta del
/// binario (`Bundle.main.bundleURL`) vive en la capa de app, no aquí.
public enum MCPConfigGenerator {

    /// Comando para `claude mcp add` (Claude Code). El `--` separa los flags de
    /// Claude del comando real. Inyecta `PASTURE_FEED_FORMAT` (ADR-007) para que
    /// el feed del server coincida con el formato actual del usuario.
    public static func claudeCodeCommand(binaryPath: String, feedFormat: FeedFormat) -> String {
        "claude mcp add pasture --env \(MCPServerConfig.feedFormatEnvKey)=\(feedFormat.rawValue) -- \(quoted(binaryPath))"
    }

    /// Bloque JSON pegable en `claude_desktop_config.json` (clave `mcpServers`).
    /// Construido con `JSONEncoder` (no concatenación) para escapar correctamente
    /// la ruta. Incluye `env.PASTURE_FEED_FORMAT` (ADR-007).
    public static func claudeDesktopJSON(binaryPath: String, feedFormat: FeedFormat) -> String {
        let config = DesktopConfig(
            mcpServers: ["pasture": ServerEntry(
                command: binaryPath,
                env: [MCPServerConfig.feedFormatEnvKey: feedFormat.rawValue])])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: — Helpers

    /// Entrecomilla una ruta si contiene espacios, para que el shell la trate
    /// como un solo argumento.
    private static func quoted(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }

    private struct DesktopConfig: Encodable {
        let mcpServers: [String: ServerEntry]
    }

    private struct ServerEntry: Encodable {
        let command: String
        let env: [String: String]
    }
}
