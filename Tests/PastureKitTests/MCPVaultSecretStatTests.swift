import Testing
import Foundation
@testable import PastureKit

/// SEC-M9 (D4 / COND-D4-2): estadística de secretos del vault para la UX de
/// registro. Lógica pura testeable; la pestaña MCP la muestra antes de copiar la
/// config, para que el consentimiento del registro no sea ciego.
@Suite struct MCPVaultSecretStatTests {

    private func makeVault() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-stat-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, to relativePath: String, in root: URL) {
        let url = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func cleanVaultReportsZeroSecrets() {
        let root = makeVault()
        write("just notes", to: "a.md", in: root)
        write("more notes", to: "proyecto-X/b.md", in: root)
        let stat = MCPVaultStats.secretStats(vaultRoot: root)
        #expect(stat.fileCount == 0)
        #expect(stat.summaryLines.isEmpty)
    }

    @Test func vaultWithSecretsReportsCountAndFamilies() {
        let root = makeVault()
        write("key sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUV", to: "leak.md", in: root)
        write("token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", to: "proyecto-X/creds.md", in: root)
        write("clean file", to: "ok.md", in: root)

        let stat = MCPVaultStats.secretStats(vaultRoot: root)
        #expect(stat.fileCount == 2)   // dos ficheros con secretos
        // Las líneas resumen mencionan las familias, nunca el valor.
        let joined = stat.summaryLines.joined(separator: " ")
        #expect(joined.contains("Anthropic key"))
        #expect(joined.contains("GitHub token"))
        #expect(!joined.contains("sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUV"))
    }

    @Test func statScansRootAndCollections() {
        let root = makeVault()
        write("token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", to: "notas/deep.md", in: root)
        let stat = MCPVaultStats.secretStats(vaultRoot: root)
        #expect(stat.fileCount == 1)
    }
}
