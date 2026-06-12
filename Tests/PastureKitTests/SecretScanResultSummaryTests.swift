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
}
