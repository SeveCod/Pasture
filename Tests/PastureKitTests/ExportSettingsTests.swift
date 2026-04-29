import Testing
import Foundation
@testable import PastureKit

@Suite("ExportSettings")
struct ExportSettingsTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.sevecod.pasture.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Save and load roundtrip")
    func saveLoadRoundtrip() {
        let defaults = makeIsolatedDefaults()
        let destinations = [
            ExportDestination(name: "Project A", path: "/tmp/a.md"),
            ExportDestination(name: "Project B", path: "/tmp/b.md"),
        ]
        ExportSettings.saveDestinations(destinations, to: defaults)
        let loaded = ExportSettings.loadDestinations(from: defaults)
        #expect(loaded.count == 2)
        #expect(loaded[0].name == "Project A")
        #expect(loaded[1].path == "/tmp/b.md")
    }

    @Test("Load returns empty array when no data")
    func loadEmpty() {
        let defaults = makeIsolatedDefaults()
        let loaded = ExportSettings.loadDestinations(from: defaults)
        #expect(loaded.isEmpty)
    }

    @Test("Default destination ID roundtrip")
    func defaultIDRoundtrip() {
        let defaults = makeIsolatedDefaults()
        let id = UUID()
        ExportSettings.setDefaultDestinationID(id, in: defaults)
        #expect(ExportSettings.defaultDestinationID(from: defaults) == id)
    }

    @Test("Default destination ID is nil when not set")
    func defaultIDNil() {
        let defaults = makeIsolatedDefaults()
        #expect(ExportSettings.defaultDestinationID(from: defaults) == nil)
    }

    @Test("Clear default destination ID")
    func clearDefaultID() {
        let defaults = makeIsolatedDefaults()
        ExportSettings.setDefaultDestinationID(UUID(), in: defaults)
        ExportSettings.setDefaultDestinationID(nil, in: defaults)
        #expect(ExportSettings.defaultDestinationID(from: defaults) == nil)
    }
}
