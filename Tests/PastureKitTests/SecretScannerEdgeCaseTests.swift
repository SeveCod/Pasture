import Testing
import Foundation
@testable import PastureKit

/// F1 — Edge cases del SecretScanner detectados en QA v1.4.
/// Documenta comportamientos conocidos ante inputs degenerados que el senior-dev
/// debe evaluar: secretos partidos en líneas, Unicode en el contenido, y fichero vacío.
@Suite("SecretScanner edge cases (QA v1.4)")
struct SecretScannerEdgeCaseTests {

    // MARK: — Secreto partido en líneas (falso negativo conocido)

    /// Un token GitHub partido en dos líneas con la parte de prefijo demasiado corta
    /// NO se detecta. Es un falso negativo documentado: el escáner es line-by-line
    /// y necesita >=20 chars alfanuméricos en la misma línea que el prefijo.
    /// El diseño acepta esto (best-effort, no garantía — SEC-5).
    @Test("Token split across lines with short first segment is not detected (known false negative)")
    func tokenSplitAcrossLines() {
        // Primera línea: "ghp_" + 6 chars (< 20 requeridos) → no detecta
        // Segunda línea: solo el resto del token sin el prefijo → no detecta
        let split = "ghp_012345\nghijklmnopqrstuvwx0123456789"
        let result = SecretScanner.scan(fileName: "split.md", content: split)
        // Documentamos el comportamiento real: no se detecta.
        // Si esto cambia (se añade detección multilínea), este test debe actualizarse.
        #expect(result.isEmpty, "Token partido en líneas con prefijo corto: falso negativo conocido")
    }

    /// Un token con la parte de prefijo suficientemente larga en la primera línea
    /// SÍ se detecta aunque esté partido (la primera línea tiene >=20 chars tras el prefijo).
    @Test("Token split across lines with long first segment IS detected")
    func tokenSplitLongFirstSegment() {
        // Primera línea: "ghp_" + 20 chars → cumple el mínimo, detecta
        let split = "ghp_0123456789abcdefghij\nklmnopqrstuvwx"
        let result = SecretScanner.scan(fileName: "split2.md", content: split)
        #expect(result.kinds.contains(.githubToken))
    }

    // MARK: — Unicode alrededor del secreto

    /// Un secreto rodeado de caracteres Unicode (emoji, caracteres CJK) se detecta.
    @Test("Detects secret surrounded by Unicode characters")
    func secretAmidUnicode() {
        let content = "配置: sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCD 🔑"
        let result = SecretScanner.scan(fileName: "unicode.md", content: content)
        #expect(result.kinds.contains(.anthropicKey))
    }

    /// Contenido 100% Unicode sin secretos no dispara nada.
    @Test("Unicode-only content without secrets is clean")
    func unicodeOnlyClean() {
        let content = "日本語のテキスト 🎌 中文内容 한국어 텍스트"
        let result = SecretScanner.scan(fileName: "unicode_clean.md", content: content)
        #expect(result.isEmpty)
    }

    // MARK: — Fichero vacío / solo espacios

    @Test("Empty content returns empty result")
    func emptyContent() {
        let result = SecretScanner.scan(fileName: "empty.md", content: "")
        #expect(result.isEmpty)
    }

    @Test("Whitespace-only content returns empty result")
    func whitespaceOnlyContent() {
        let result = SecretScanner.scan(fileName: "ws.md", content: "   \n\t\n  ")
        #expect(result.isEmpty)
    }

    // MARK: — Enmascarado (mask) con secreto vacío o muy corto

    /// El enmascarado de un secreto vacío produce "…" sin prefijo (comportamiento seguro).
    @Test("mask of empty string produces safe output")
    func maskEmptyString() {
        let masked = SecretScanner.mask("")
        // No debe ser el secreto (vacío), debe tener la marca de enmascarado.
        #expect(masked.contains("\u{2026}"))
    }

    /// El enmascarado de un secreto de un solo carácter produce "X…" (seguro).
    @Test("mask of single-char string produces safe output")
    func maskSingleChar() {
        let masked = SecretScanner.mask("X")
        #expect(masked.contains("\u{2026}"))
        // No debe revelar nada más que el primer carácter + marca.
        #expect(masked.count <= 2)
    }

    // MARK: — I-1: el cap de tamaño corta en frontera de carácter (no parte UTF-8)

    /// Un carácter multibyte (emoji de 4 bytes) que cruza la frontera del cap
    /// NO debe partirse y producir U+FFFD (replacement character). El corte
    /// respeta fronteras de carácter Unicode.
    @Test("Size cap cuts on a character boundary, never producing U+FFFD (I-1)")
    func sizeCapRespectsCharacterBoundary() {
        // Relleno hasta 2 bytes por debajo del cap, luego un emoji de 4 bytes UTF-8
        // (🔑 = F0 9F 94 91) que cruza el límite. Si se cortara por bytes crudos,
        // aparecería el carácter de reemplazo U+FFFD.
        let padBytes = SecretScanner.maxScanBytes - 2
        let padding = String(repeating: "a", count: padBytes)
        let content = padding + "🔑" + "more text"
        let capped = SecretScanner.cappedContent(content)
        #expect(!capped.contains("\u{FFFD}"), "El corte por bytes partió un carácter multibyte")
        // El cap sigue acotando el tamaño (no devuelve el contenido íntegro).
        #expect(capped.utf8.count <= SecretScanner.maxScanBytes)
    }

    /// Contenido por debajo del cap se devuelve íntegro y sin alteraciones.
    @Test("Content under the cap is returned unchanged")
    func underCapUnchanged() {
        let content = "短い 🔑 contenido con multibyte"
        #expect(SecretScanner.cappedContent(content) == content)
    }

    /// Un emoji justo en el byte del límite no introduce U+FFFD aunque quede fuera.
    @Test("Multibyte char straddling the exact cap boundary is dropped cleanly (I-1)")
    func multibyteAtExactBoundary() {
        let padding = String(repeating: "a", count: SecretScanner.maxScanBytes - 1)
        let content = padding + "🔑"
        let capped = SecretScanner.cappedContent(content)
        #expect(!capped.contains("\u{FFFD}"))
    }
}
