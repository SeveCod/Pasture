import Testing
import Foundation
@testable import PastureKit

@Suite("KeychainStore")
struct KeychainStoreTests {

    private func testService() -> String {
        "com.sevecod.pasture.test.\(UUID().uuidString)"
    }

    @Test("Save and load roundtrip")
    func saveLoadRoundtrip() throws {
        let service = testService()
        try KeychainStore.save(key: "test_key", value: "secret123", service: service)
        let loaded = KeychainStore.load(key: "test_key", service: service)
        #expect(loaded == "secret123")
        KeychainStore.delete(key: "test_key", service: service)
    }

    @Test("Load returns nil when key not found")
    func loadNonexistent() {
        let service = testService()
        #expect(KeychainStore.load(key: "nonexistent", service: service) == nil)
    }

    @Test("Save overwrites existing value")
    func saveOverwrites() throws {
        let service = testService()
        try KeychainStore.save(key: "overwrite", value: "first", service: service)
        try KeychainStore.save(key: "overwrite", value: "second", service: service)
        #expect(KeychainStore.load(key: "overwrite", service: service) == "second")
        KeychainStore.delete(key: "overwrite", service: service)
    }

    @Test("Delete removes key")
    func deleteKey() throws {
        let service = testService()
        try KeychainStore.save(key: "to_delete", value: "value", service: service)
        KeychainStore.delete(key: "to_delete", service: service)
        #expect(KeychainStore.load(key: "to_delete", service: service) == nil)
    }

    @Test("Delete is no-op for nonexistent key")
    func deleteNonexistent() {
        let service = testService()
        KeychainStore.delete(key: "never_existed", service: service)
    }

    @Test("Delete returns true whether the key existed or not")
    func deleteReturnsSuccess() throws {
        let service = testService()
        try KeychainStore.save(key: "del_ret", value: "v", service: service)
        #expect(KeychainStore.delete(key: "del_ret", service: service) == true)
        // Borrar de nuevo (ya no existe) también es "éxito": el estado deseado es "no está".
        #expect(KeychainStore.delete(key: "del_ret", service: service) == true)
    }

    @Test("Empty string saves and loads correctly")
    func emptyString() throws {
        let service = testService()
        try KeychainStore.save(key: "empty", value: "", service: service)
        #expect(KeychainStore.load(key: "empty", service: service) == "")
        KeychainStore.delete(key: "empty", service: service)
    }

    @Test("Unicode string roundtrip")
    func unicodeRoundtrip() throws {
        let service = testService()
        let value = "clé-secrète-日本語-🔑"
        try KeychainStore.save(key: "unicode", value: value, service: service)
        #expect(KeychainStore.load(key: "unicode", service: service) == value)
        KeychainStore.delete(key: "unicode", service: service)
    }

    @Test("Different services are isolated")
    func serviceIsolation() throws {
        let service1 = testService()
        let service2 = testService()
        try KeychainStore.save(key: "shared_key", value: "value1", service: service1)
        try KeychainStore.save(key: "shared_key", value: "value2", service: service2)
        #expect(KeychainStore.load(key: "shared_key", service: service1) == "value1")
        #expect(KeychainStore.load(key: "shared_key", service: service2) == "value2")
        KeychainStore.delete(key: "shared_key", service: service1)
        KeychainStore.delete(key: "shared_key", service: service2)
    }
}
