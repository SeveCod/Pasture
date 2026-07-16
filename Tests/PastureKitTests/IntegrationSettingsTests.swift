import Foundation
import Testing
@testable import PastureKit

@Suite("IntegrationSettings")
struct IntegrationSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let name = "IntegrationSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreSafe() {
        let defaults = makeDefaults()
        #expect(IntegrationSettings.hideDockIcon(from: defaults) == false)
        #expect(IntegrationSettings.globalHotkeysEnabled(from: defaults) == false)
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == nil)
    }

    @Test func roundTripAllSettings() {
        let defaults = makeDefaults()
        let id = UUID()
        IntegrationSettings.setHideDockIcon(true, in: defaults)
        IntegrationSettings.setGlobalHotkeysEnabled(true, in: defaults)
        IntegrationSettings.setDefaultPresetID(id, in: defaults)
        #expect(IntegrationSettings.hideDockIcon(from: defaults) == true)
        #expect(IntegrationSettings.globalHotkeysEnabled(from: defaults) == true)
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == id)
    }

    @Test func clearingDefaultPresetID() {
        let defaults = makeDefaults()
        IntegrationSettings.setDefaultPresetID(UUID(), in: defaults)
        IntegrationSettings.setDefaultPresetID(nil, in: defaults)
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == nil)
    }

    @Test func corruptPresetIDDegradesToNil() {
        let defaults = makeDefaults()
        defaults.set("not-a-uuid", forKey: "pastureDefaultPresetID")
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == nil)
    }
}
