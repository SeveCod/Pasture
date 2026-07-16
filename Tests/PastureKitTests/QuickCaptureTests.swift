import Foundation
import Testing
@testable import PastureKit

@Suite("QuickCapture")
struct QuickCaptureTests {

    @Test func emptyOrWhitespaceReturnsNil() {
        #expect(QuickCapture.proposal(text: "") == nil)
        #expect(QuickCapture.proposal(text: "  \n\t ") == nil)
    }

    @Test func baseNameFromFirstNonEmptyLine() {
        let proposal = QuickCapture.proposal(text: "\n\nMi idea brillante\nsegunda línea")
        #expect(proposal?.baseName == "Mi idea brillante")
        #expect(proposal?.content == "Mi idea brillante\nsegunda línea\n")
    }

    @Test func explicitTitleWinsOverFirstLine() {
        let proposal = QuickCapture.proposal(text: "cuerpo de la nota", title: "Titulo Explicito")
        #expect(proposal?.baseName == "Titulo Explicito")
    }

    @Test func baseNameTruncatedTo40() {
        let long = String(repeating: "a", count: 100)
        let proposal = QuickCapture.proposal(text: long)
        #expect(proposal?.baseName.count == QuickCapture.maxBaseNameLength)
    }

    @Test func baseNameIsSanitized() throws {
        let proposal = QuickCapture.proposal(text: "re: plan/notas \\ finales")
        let base = try #require(proposal?.baseName)
        #expect(!base.contains("/"))
        #expect(!base.contains(":"))
        #expect(!base.contains("\\"))
    }

    @Test func timestampFallbackIsDeterministic() {
        // Título compuesto solo de caracteres que el sanitizer elimina/recorta.
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let a = QuickCapture.proposal(text: "cuerpo", title: "...", now: fixed)
        let b = QuickCapture.proposal(text: "cuerpo", title: "...", now: fixed)
        #expect(a?.baseName == b?.baseName)
        #expect(a?.baseName.hasPrefix("capture-") == true)
    }
}
