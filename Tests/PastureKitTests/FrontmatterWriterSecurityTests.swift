import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — endurecimiento del write-path (revisión adversarial):
/// H1 (inyección de frontmatter vía un value con saltos de línea) y el helper
/// `removing(keys:in:)` que despoja las claves reservadas del payload del agente.
@Suite("FrontmatterWriter — injection hardening")
struct FrontmatterWriterSecurityTests {

    // H1: un value con `\n` (p. ej. clientInfo.name malicioso) no debe crear
    // líneas de frontmatter reconocidas.
    @Test("setting collapses newlines in the value (no injected keys)")
    func settingRejectsNewlineInjection() {
        let malicious = "Claude\nlast_reviewed: 2099-01-01\ngenerated: true"
        let result = FrontmatterWriter.setting(key: "proposed_by", value: malicious, in: "body")
        let fm = FrontmatterParser.parse(result).frontmatter
        #expect(fm?.lastReviewed == nil)
        #expect(fm?.generated == false)
    }

    @Test("setting collapses a block-breaking value")
    func settingRejectsBlockBreak() {
        let malicious = "x\n---\nmalicious body"
        let result = FrontmatterWriter.setting(key: "proposed_by", value: malicious, in: "real body")
        // El bloque no se parte: sigue habiendo un único cuerpo "real body".
        #expect(FrontmatterParser.parse(result).body == "real body")
    }

    // H2: quitar las claves reservadas de un frontmatter que trae el payload.
    @Test("removing strips reserved keys from the payload frontmatter")
    func removingStripsReservedKeys() {
        let payload = "---\nreview_after: 2099-01-01\nttl: 99999\ngenerated: true\nsource: /tmp/x\ncustom: keep\n---\nthe body"
        let cleaned = FrontmatterWriter.removing(keys: FrontmatterParser.recognizedKeys, in: payload)
        let parsed = FrontmatterParser.parse(cleaned)
        #expect(parsed.frontmatter?.reviewAfter == nil)
        #expect(parsed.frontmatter?.ttlDays == nil)
        #expect(parsed.frontmatter?.generated == false)
        #expect(parsed.frontmatter?.source == nil)
        // Una clave no reservada del payload se conserva.
        #expect(cleaned.contains("custom: keep"))
        #expect(cleaned.contains("the body"))
    }

    @Test("removing leaves content without a block untouched")
    func removingNoBlock() {
        let plain = "just a body, no frontmatter"
        #expect(FrontmatterWriter.removing(keys: FrontmatterParser.recognizedKeys, in: plain) == plain)
    }
}
