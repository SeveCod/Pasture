import Testing
import Foundation
@testable import PastureKit

/// F4 — Persistencia del formato de feed. Patrón ExportSettings (UserDefaults).
/// ADR-005: ortogonal a ExportFileFormat (otra clave, otro setting).
@Suite("FeedFormatSettings")
struct FeedFormatSettingsTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.sevecod.pasture.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Defaults to .xml when not set (retrocompat)")
    func defaultIsXML() {
        let defaults = makeIsolatedDefaults()
        #expect(FeedFormatSettings.feedFormat(from: defaults) == .xml)
    }

    @Test("Roundtrip for all formats")
    func roundtrip() {
        let defaults = makeIsolatedDefaults()
        for format in FeedFormat.allCases {
            FeedFormatSettings.setFeedFormat(format, in: defaults)
            #expect(FeedFormatSettings.feedFormat(from: defaults) == format)
        }
    }

    @Test("Falls back to .xml on unknown stored value")
    func unknownValueFallsBack() {
        let defaults = makeIsolatedDefaults()
        defaults.set("yaml", forKey: "com.sevecod.pasture.feedFormat")
        #expect(FeedFormatSettings.feedFormat(from: defaults) == .xml)
    }

    @Test("Has a didChange notification name")
    func hasNotification() {
        #expect(FeedFormatSettings.didChangeNotification.rawValue == "PastureFeedFormatSettingsDidChange")
    }

    @Test("FeedFormatSettings key is distinct from ExportSettings (ADR-005)")
    func orthogonalKeys() {
        // Cambiar el formato de feed no debe tocar el formato de export de fichero.
        let defaults = makeIsolatedDefaults()
        ExportSettings.setFileFormat(.plainText, in: defaults)
        FeedFormatSettings.setFeedFormat(.markdown, in: defaults)
        #expect(ExportSettings.fileFormat(from: defaults) == .plainText)
        #expect(FeedFormatSettings.feedFormat(from: defaults) == .markdown)
    }
}
