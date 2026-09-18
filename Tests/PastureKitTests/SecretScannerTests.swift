import Testing
import Foundation
@testable import PastureKit

/// F1 — SecretScanner. Red de seguridad best-effort contra fuga de credenciales.
/// SEC-2 (catálogo testeado, 0 falsos negativos), SEC-3 (ReDoS),
/// SEC-4 (el valor del secreto nunca se expone).
@Suite("SecretScanner")
struct SecretScannerTests {

    // MARK: — Positivos del catálogo (SEC-2: 0 falsos negativos)

    @Test("Detects Anthropic key (sk-ant-)")
    func detectsAnthropic() {
        let secret = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        let result = SecretScanner.scan(fileName: "keys.md", content: "key = \(secret)")
        #expect(result.kinds.contains(.anthropicKey))
    }

    @Test("Detects GitHub token (ghp_)")
    func detectsGitHubClassic() {
        let result = SecretScanner.scan(fileName: "ci.md", content: "token: ghp_0123456789abcdefghijklmnopqrstuvwx")
        #expect(result.kinds.contains(.githubToken))
    }

    @Test("Detects GitHub token variants (gho_/ghu_/ghs_)")
    func detectsGitHubVariants() {
        for prefix in ["gho_", "ghu_", "ghs_"] {
            let result = SecretScanner.scan(fileName: "f.md", content: "\(prefix)0123456789abcdefghijklmnopqrstuvwx")
            #expect(result.kinds.contains(.githubToken))
        }
    }

    @Test("Detects AWS access key (AKIA...)")
    func detectsAWS() {
        let result = SecretScanner.scan(fileName: "aws.md", content: "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
        #expect(result.kinds.contains(.awsAccessKey))
    }

    @Test("Detects PEM private key block")
    func detectsPEM() {
        let pem = "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n-----END RSA PRIVATE KEY-----"
        let result = SecretScanner.scan(fileName: "id_rsa.md", content: pem)
        #expect(result.kinds.contains(.pemPrivateKey))
    }

    @Test("Detects generic OpenAI-style key (sk-)")
    func detectsOpenAIGeneric() {
        let result = SecretScanner.scan(fileName: "openai.md", content: "sk-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH")
        #expect(result.kinds.contains(.openAIKey))
    }

    @Test("Detects modern OpenAI project key (sk-proj-)")
    func detectsOpenAIProject() {
        // Formato por defecto de OpenAI desde 2024. El '-' tras 'proj' rompe el
        // patrón genérico sk-[A-Za-z0-9]{20,}, por eso necesita patrón propio.
        let secret = "sk-proj-" + "abcDEF123-ghiJKL456_mnoPQR789stuVWX0"
        let result = SecretScanner.scan(fileName: "openai.md", content: "OPENAI_API_KEY=\(secret)")
        #expect(result.kinds.contains(.openAIKey))
    }

    @Test("Detects GitHub fine-grained token (github_pat_)")
    func detectsGitHubFineGrained() {
        // Formato recomendado por GitHub desde 2023. El patrón clásico gh[opus]_ no lo cubre.
        let secret = "github_pat_" + "11ABCDE0123456789_abcdefghijklmnopqrstuvwxyz0123456789"
        let result = SecretScanner.scan(fileName: "ci.md", content: "token: \(secret)")
        #expect(result.kinds.contains(.githubToken))
    }

    @Test("Detects AWS temporary/STS access key (ASIA...)")
    func detectsAWSTemporary() {
        // Fixture por concatenación: la variante ASIA de la clave de ejemplo de AWS
        // no está en la allowlist del secret scanning de GitHub (la AKIA sí).
        let secret = "ASIA" + "IOSFODNN7EXAMPLE"
        let result = SecretScanner.scan(fileName: "aws.md", content: "AWS_ACCESS_KEY_ID=\(secret)")
        #expect(result.kinds.contains(.awsAccessKey))
    }

    @Test("Detects Slack token (xox)")
    func detectsSlack() {
        // Fixture construido por concatenación para no disparar el push
        // protection de GitHub (el literal completo parece un token real).
        let token = "xoxb-" + "1234567890-abcdefghijklmnopqrstuvwx"
        let result = SecretScanner.scan(fileName: "slack.md", content: token)
        #expect(result.kinds.contains(.slackToken))
    }

    // Audit 360 (A1): estas tres familias NO estaban en el catálogo. La de
    // OpenRouter es la grave — es el segundo proveedor que la propia app integra
    // y cuya clave guarda en el llavero, y el escáner es un gate que BLOQUEA en
    // HeadlessFeed y en PackWriter, así que una clave sin detectar se escribía en
    // el CLAUDE.md de un repo del usuario camino del commit.
    @Test("Detects OpenRouter key (sk-or-v1-)")
    func detectsOpenRouter() {
        // Por concatenación (push protection). Forma real: sk-or-v1- + 64 hex.
        let secret = "sk-or-" + "v1-" + String(repeating: "a1b2c3d4", count: 8)
        let result = SecretScanner.scan(fileName: "keys.md", content: "OPENROUTER=\(secret)")
        #expect(result.kinds.contains(.openRouterKey))
    }

    @Test("Detects Google API key (AIza)")
    func detectsGoogleAPIKey() {
        let secret = "AIza" + String(repeating: "B", count: 35)
        let result = SecretScanner.scan(fileName: "keys.md", content: secret)
        #expect(result.kinds.contains(.googleAPIKey))
    }

    @Test("Detects Stripe live key, ignores test key")
    func detectsStripeLiveOnly() {
        let live = "sk_" + "live_" + String(repeating: "c3d4e5f6", count: 4)
        let test = "sk_" + "test_" + String(repeating: "c3d4e5f6", count: 4)
        #expect(SecretScanner.scan(fileName: "k.md", content: live).kinds.contains(.stripeKey))
        // Una clave `test` de Stripe no es sensible: hacer saltar un gate que
        // bloquea por ella sería fricción sin ganancia. Decisión deliberada.
        #expect(!SecretScanner.scan(fileName: "k.md", content: test).kinds.contains(.stripeKey))
    }

    // MARK: — Invariante: el catálogo cubre TODOS los proveedores de la app

    /// La guardia que habría cazado A1 y que cazará al siguiente proveedor.
    ///
    /// El defecto no fue "falta un patrón": fue que el catálogo del escáner y la
    /// lista de proveedores que la app sabe almacenar en el llavero derivaron sin
    /// que nada lo notase. Este test barre `AIProviderKind.allCases`, así que
    /// añadir un proveedor sin añadir su patrón deja de compilar (el `switch` es
    /// exhaustivo) o falla aquí.
    @Test("Toda clave de un proveedor soportado por la app es detectable")
    func everySupportedProviderIsScannable() {
        for provider in AIProviderKind.allCases {
            let (muestra, esperada): (String, SecretKind) = switch provider {
            case .anthropic:
                ("sk-ant-" + "api03-" + String(repeating: "a1b2c3d4", count: 5), .anthropicKey)
            case .openRouter:
                ("sk-or-" + "v1-" + String(repeating: "a1b2c3d4", count: 8), .openRouterKey)
            }
            let result = SecretScanner.scan(fileName: "k.md", content: "KEY=\(muestra)")
            #expect(result.kinds.contains(esperada),
                    "el proveedor \(provider.rawValue) se guarda en el llavero pero su clave no la detecta el escáner, que es un gate que bloquea en HeadlessFeed y PackWriter")
        }
    }

    // MARK: — Discriminación de familias

    // sk-ant- debe clasificarse como Anthropic, NO como genérico sk-.
    @Test("sk-ant- is classified as Anthropic, not generic OpenAI")
    func anthropicNotMisclassified() {
        let secret = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        let result = SecretScanner.scan(fileName: "k.md", content: secret)
        #expect(result.kinds.contains(.anthropicKey))
        #expect(!result.kinds.contains(.openAIKey))
    }

    // MARK: — Negativos (no disparar en prosa/identificadores legítimos)

    @Test("Plain prose does not trigger")
    func proseClean() {
        let result = SecretScanner.scan(fileName: "doc.md", content: "This is a normal markdown document about cows and pastures.")
        #expect(result.isEmpty)
    }

    @Test("UUID does not trigger")
    func uuidClean() {
        let result = SecretScanner.scan(fileName: "u.md", content: "id: 550e8400-e29b-41d4-a716-446655440000")
        #expect(result.isEmpty)
    }

    @Test("Git SHA hash does not trigger")
    func shaClean() {
        let result = SecretScanner.scan(fileName: "g.md", content: "commit 506de75e62713ef66d0f5750ca8b9c1234567890")
        #expect(result.isEmpty)
    }

    @Test("Short sk- fragment does not trigger (too short to be a key)")
    func shortSkClean() {
        let result = SecretScanner.scan(fileName: "s.md", content: "the sku-123 and sk-abc are fine")
        #expect(result.isEmpty)
    }

    @Test("AKIA without 16 trailing chars does not trigger")
    func partialAKIAClean() {
        let result = SecretScanner.scan(fileName: "a.md", content: "AKIA123 is too short")
        #expect(result.isEmpty)
    }

    // MARK: — SEC-4: el valor del secreto NUNCA se expone

    @Test("Masked snippet never contains the full secret (SEC-4)")
    func maskedSnippetHidesSecret() {
        let secret = "sk-ant-api03-SUPERSECRETVALUE0123456789abcdefSECRET"
        let result = SecretScanner.scan(fileName: "k.md", content: secret)
        #expect(!result.isEmpty)
        for match in result.matches {
            // El snippet enmascarado no debe contener el secreto completo.
            #expect(!match.maskedSnippet.contains(secret))
            // Debe contener la marca de enmascarado.
            #expect(match.maskedSnippet.contains("\u{2026}"))
            // No debe contener la parte central sensible del secreto.
            #expect(!match.maskedSnippet.contains("SUPERSECRETVALUE"))
        }
    }

    @Test("Match reports file name and 1-based line number")
    func reportsLocation() {
        let content = "line one\nline two\nkey = ghp_0123456789abcdefghijklmnopqrstuvwx"
        let result = SecretScanner.scan(fileName: "config.md", content: content)
        #expect(!result.isEmpty)
        let match = result.matches.first!
        #expect(match.fileName == "config.md")
        #expect(match.lineNumber == 3)
    }

    // MARK: — grouped() (multi-fichero, multi-tipo)

    @Test("grouped() aggregates by file then by kind")
    func groupedByFileAndKind() {
        let inputs = [
            SecretScanner.Input(fileName: "a.md", content: "ghp_0123456789abcdefghijklmnopqrstuvwx"),
            SecretScanner.Input(fileName: "b.md", content: "AKIAIOSFODNN7EXAMPLE\nsk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCD"),
        ]
        let result = SecretScanner.scan(inputs)
        let grouped = result.grouped()
        #expect(grouped["a.md"]?[.githubToken] != nil)
        #expect(grouped["b.md"]?[.awsAccessKey] != nil)
        #expect(grouped["b.md"]?[.anthropicKey] != nil)
    }

    @Test("Empty selection yields empty result")
    func emptyInputs() {
        #expect(SecretScanner.scan([]).isEmpty)
    }

    @Test("kinds returns unique detected families")
    func uniqueKinds() {
        let content = "ghp_0123456789abcdefghijklmnopqrstuvwx\nghp_zzzzzzzzzzabcdefghijklmnopqrstuvwx"
        let result = SecretScanner.scan(fileName: "f.md", content: content)
        #expect(result.kinds == Set([.githubToken]))
    }

    @Test("All SecretKind have a display name")
    func displayNames() {
        for kind in SecretKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    // MARK: — SEC-3: defensa ReDoS / inputs patológicos

    @Test("Pathological large input completes in bounded time (SEC-3)", .timeLimit(.minutes(1)))
    func redosLargeInput() {
        // Cadenas patológicas: muchos backticks-no, muchos guiones sin cierre PEM,
        // y un input grande. No debe colgar.
        let dashes = String(repeating: "-", count: 500_000)
        let pemBait = "-----BEGIN " + String(repeating: "A", count: 200_000)
        let skBait = "sk-" + String(repeating: "a", count: 300_000)
        let big = dashes + "\n" + pemBait + "\n" + skBait
        let result = SecretScanner.scan(fileName: "huge.md", content: big)
        // El objetivo es que TERMINE (lo garantiza .timeLimit). Además verificamos
        // que el escaneo corrió realmente sobre el input grande: skBait es un sk-
        // válido dentro del cap de 2 MB, así que debe detectarse como openAIKey.
        #expect(result.kinds.contains(.openAIKey))
    }

    @Test("Very large clean input completes quickly (SEC-3)", .timeLimit(.minutes(1)))
    func largeCleanInput() {
        let content = String(repeating: "The quick brown fox jumps over the lazy dog.\n", count: 100_000)
        let result = SecretScanner.scan(fileName: "big.md", content: content)
        #expect(result.isEmpty)
    }

    // MARK: — SEC-3: límite de tamaño de input

    @Test("Input above size cap is truncated, not scanned whole")
    func sizeCapApplied() {
        // Un secreto colocado más allá del límite de escaneo no se detecta:
        // el cap protege contra inputs gigantes a coste de cobertura en la cola.
        let padding = String(repeating: "x", count: SecretScanner.maxScanBytes + 1000)
        let content = padding + "\nghp_0123456789abcdefghijklmnopqrstuvwx"
        let result = SecretScanner.scan(fileName: "capped.md", content: content)
        // El token ghp_ está más allá del cap de escaneo, así que NO debe detectarse:
        // el cap trunca el contenido antes de llegar a él.
        #expect(result.isEmpty)
    }

    @Test("Pattern catalog compiles without crashing")
    func patternCatalogCompiles() {
        // Fuerza la inicialización perezosa del catálogo (try! en compile()).
        // Un patrón malformado en el futuro reventaría aquí, en CI, no en producción.
        let result = SecretScanner.scan(fileName: "x.md", content: "plain text without secrets")
        #expect(result.isEmpty)
    }
}
