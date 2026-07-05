import Testing
import Foundation
@testable import PastureKit

/// Context Compiler (v1.6) — cabecera de sync + SHA-256 + estado de conflicto.
@Suite struct SyncMarkerTests {

    @Test func composeRoundTripsHeaderAndBody() throws {
        let composed = SyncMarker.compose(packName: "mi-pack", body: "cuerpo real\ncon líneas")
        let parsed = try #require(SyncMarker.parse(composed))
        #expect(parsed.packName == "mi-pack")
        #expect(parsed.body == "cuerpo real\ncon líneas")
        #expect(parsed.bodyHash == SyncMarker.sha256("cuerpo real\ncon líneas"))
    }

    @Test func sha256IsStableAndDeterministic() {
        let a = SyncMarker.sha256("hola")
        let b = SyncMarker.sha256("hola")
        #expect(a == b)
        #expect(a.count == 64)   // 32 bytes en hex
        #expect(a != SyncMarker.sha256("holaa"))
    }

    @Test func parseRejectsContentWithoutMarker() {
        #expect(SyncMarker.parse("# Un CLAUDE.md escrito a mano\nsin cabecera") == nil)
        #expect(SyncMarker.parse("") == nil)
    }

    /// Un nombre de pack con ' | ' no debe romper la extracción del hash.
    @Test func parseHandlesPipeInPackName() throws {
        let composed = SyncMarker.compose(packName: "reglas | comunes", body: "x")
        let parsed = try #require(SyncMarker.parse(composed))
        #expect(parsed.bodyHash == SyncMarker.sha256("x"))
        #expect(parsed.body == "x")
    }

    @Test func bodyWithCRLFAndMultibyteRoundTrips() throws {
        let body = "línea1\r\nlínea2 — €ñ 🐄\r\n"
        let composed = SyncMarker.compose(packName: "p", body: body)
        let parsed = try #require(SyncMarker.parse(composed))
        #expect(parsed.body == body)
        #expect(parsed.bodyHash == SyncMarker.sha256(body))
    }

    // MARK: — Estado de conflicto

    @Test func stateIsTargetMissingWhenNil() {
        #expect(SyncMarker.state(existingFileContent: nil) == .targetMissing)
    }

    @Test func stateIsCleanForUntouchedPastureFile() {
        let composed = SyncMarker.compose(packName: "p", body: "cuerpo intacto")
        #expect(SyncMarker.state(existingFileContent: composed) == .clean)
    }

    @Test func stateIsConflictWhenBodyEditedByHand() {
        var composed = SyncMarker.compose(packName: "p", body: "cuerpo original")
        composed += "\nedición manual del humano"   // cambia el cuerpo, no la cabecera
        #expect(SyncMarker.state(existingFileContent: composed) == .conflict)
    }

    @Test func stateIsConflictForFileWithoutMarker() {
        #expect(SyncMarker.state(existingFileContent: "# CLAUDE.md preexistente\nreglas") == .conflict)
    }
}
