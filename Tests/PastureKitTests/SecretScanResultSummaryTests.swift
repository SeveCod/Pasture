import Testing
@testable import PastureKit

/// F1 — Resumen legible de detecciones para el diálogo de aviso.
/// SEC-4 (no expone el valor del secreto) + SEC-5 (lenguaje "conocidos", sin garantía).
@Suite("SecretScanResult summary")
struct SecretScanResultSummaryTests {

    @Test("Summary lists file and kind, never the secret value (SEC-4)")
    func summaryHidesSecret() {
        let secret = "ghp_SUPERSECRET0123456789abcdefghij"
        let result = SecretScanner.scan(fileName: "config.md", content: secret)
        let summary = result.summaryLines()
        let joined = summary.joined(separator: "\n")
        #expect(joined.contains("config.md"))
        #expect(joined.contains(SecretKind.githubToken.displayName))
        #expect(!joined.contains(secret))
        #expect(!joined.contains("SUPERSECRET"))
    }

    @Test("Summary groups multiple kinds per file")
    func summaryGroupsKinds() {
        let inputs = [
            SecretScanner.Input(
                fileName: "secrets.md",
                content: "AKIAIOSFODNN7EXAMPLE\nsk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
            )
        ]
        let result = SecretScanner.scan(inputs)
        let summary = result.summaryLines()
        let joined = summary.joined(separator: "\n")
        #expect(joined.contains(SecretKind.awsAccessKey.displayName))
        #expect(joined.contains(SecretKind.anthropicKey.displayName))
        #expect(joined.contains("secrets.md"))
    }

    @Test("Empty result yields empty summary")
    func emptySummary() {
        #expect(SecretScanResult(matches: []).summaryLines().isEmpty)
    }

    /// Fuente única del texto del diálogo de aviso (antes duplicado en
    /// ContentView y MenuBarView). SEC-4: el mensaje nunca lleva el valor.
    @Test("Alert message carries the summary and the best-effort caveat")
    func alertMessageCarriesSummaryAndCaveat() {
        let token = "sk-ant-" + "api03-" + String(repeating: "a", count: 24)
        let result = SecretScanner.scan(fileName: "note.md", content: "key: \(token)")
        let message = result.alertMessage
        #expect(message.contains("Pasture found patterns that look like known credentials"))
        #expect(message.contains("best-effort check"))
        #expect(!result.summaryLines().isEmpty)
        for line in result.summaryLines() {
            #expect(message.contains(line))
        }
        #expect(!message.contains(token))
    }
}
