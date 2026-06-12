import Foundation

/// Estadística de secretos del vault para la UX de registro MCP (SEC-M9 / D4).
///
/// Reusa `SecretScanner` sobre `~/.pasture/` para que el consentimiento del
/// registro no sea ciego: el usuario VE, antes de copiar la config, si su vault
/// contiene patrones de secreto. Escaneo bajo demanda (lo invoca la pestaña MCP),
/// NO en cada keystroke.
public enum MCPVaultStats {

    public struct SecretStats: Sendable, Equatable {
        /// Número de ficheros con al menos un secreto detectado.
        public let fileCount: Int
        /// Resumen legible por fichero (familia + fichero), SIN valores (SEC-M8).
        public let summaryLines: [String]

        public init(fileCount: Int, summaryLines: [String]) {
            self.fileCount = fileCount
            self.summaryLines = summaryLines
        }
    }

    /// Escanea raíz + colecciones del vault (vía MCPTools.enumerateVaultFiles, que
    /// filtra ocultos y symlinks) y agrega los hallazgos del `SecretScanner`.
    public static func secretStats(vaultRoot: URL) -> SecretStats {
        let files = MCPTools.enumerateVaultFiles(vaultRoot: vaultRoot)
        let inputs = files.compactMap { entry -> SecretScanner.Input? in
            guard let content = try? String(contentsOf: entry.url, encoding: .utf8) else { return nil }
            return SecretScanner.Input(fileName: entry.relativePath, content: content)
        }
        let result = SecretScanner.scan(inputs)
        let filesWithSecrets = Set(result.matches.map(\.fileName))
        return SecretStats(
            fileCount: filesWithSecrets.count,
            summaryLines: result.summaryLines())
    }
}
