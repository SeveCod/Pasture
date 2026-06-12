import Testing
import Foundation
@testable import PastureKit

/// F2 — Presets de selección. Modelo + store.
/// SEC-7 (solo rutas relativas + nombre, nunca contenido), SEC-8 (validación de nombre).
@Suite("SelectionPreset + Store")
struct SelectionPresetTests {

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "com.sevecod.pasture.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: — Codable

    @Test("Codable roundtrip preserves fields (SEC-7: only name + relative paths)")
    func codableRoundtrip() throws {
        let preset = SelectionPreset(name: "Project X", relativePaths: ["a.md", "sub/b.md"])
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(SelectionPreset.self, from: data)
        #expect(decoded.id == preset.id)
        #expect(decoded.name == "Project X")
        #expect(decoded.relativePaths == ["a.md", "sub/b.md"])
        // SEC-7: el JSON no debe contener un campo de contenido.
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("content"))
    }

    // MARK: — Store CRUD

    @Test("Save and load roundtrip")
    func saveLoadRoundtrip() {
        let defaults = makeIsolatedDefaults()
        let presets = [
            SelectionPreset(name: "A", relativePaths: ["x.md"]),
            SelectionPreset(name: "B", relativePaths: ["y.md", "z.md"]),
        ]
        SelectionPresetStore.save(presets, to: defaults)
        let loaded = SelectionPresetStore.load(from: defaults)
        #expect(loaded.count == 2)
        #expect(loaded[0].name == "A")
        #expect(loaded[1].relativePaths == ["y.md", "z.md"])
    }

    @Test("Load returns empty when nothing stored")
    func loadEmpty() {
        let defaults = makeIsolatedDefaults()
        #expect(SelectionPresetStore.load(from: defaults).isEmpty)
    }

    @Test("Upsert inserts a new preset")
    func upsertInsert() {
        let defaults = makeIsolatedDefaults()
        let preset = SelectionPreset(name: "New", relativePaths: ["a.md"])
        SelectionPresetStore.upsert(preset, in: defaults)
        #expect(SelectionPresetStore.load(from: defaults).count == 1)
    }

    @Test("Upsert replaces by id")
    func upsertReplace() {
        let defaults = makeIsolatedDefaults()
        var preset = SelectionPreset(name: "Original", relativePaths: ["a.md"])
        SelectionPresetStore.upsert(preset, in: defaults)
        preset.name = "Updated"
        preset.relativePaths = ["b.md"]
        SelectionPresetStore.upsert(preset, in: defaults)
        let loaded = SelectionPresetStore.load(from: defaults)
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "Updated")
        #expect(loaded[0].relativePaths == ["b.md"])
    }

    @Test("Delete removes by id")
    func deleteByID() {
        let defaults = makeIsolatedDefaults()
        let keep = SelectionPreset(name: "Keep", relativePaths: ["k.md"])
        let drop = SelectionPreset(name: "Drop", relativePaths: ["d.md"])
        SelectionPresetStore.save([keep, drop], to: defaults)
        SelectionPresetStore.delete(id: drop.id, in: defaults)
        let loaded = SelectionPresetStore.load(from: defaults)
        #expect(loaded.count == 1)
        #expect(loaded[0].id == keep.id)
    }

    @Test("Rename changes name, keeps paths")
    func rename() {
        let defaults = makeIsolatedDefaults()
        let preset = SelectionPreset(name: "Old", relativePaths: ["a.md", "b.md"])
        SelectionPresetStore.upsert(preset, in: defaults)
        SelectionPresetStore.rename(id: preset.id, to: "New", in: defaults)
        let loaded = SelectionPresetStore.load(from: defaults)
        #expect(loaded[0].name == "New")
        #expect(loaded[0].relativePaths == ["a.md", "b.md"])
    }

    @Test("preset(named:) finds case-insensitively")
    func presetNamed() {
        let defaults = makeIsolatedDefaults()
        SelectionPresetStore.upsert(SelectionPreset(name: "Project X", relativePaths: ["a.md"]), in: defaults)
        #expect(SelectionPresetStore.preset(named: "project x", in: defaults) != nil)
        #expect(SelectionPresetStore.preset(named: "Nope", in: defaults) == nil)
    }

    // MARK: — SEC-8: validación de nombre

    @Test("Sanitizes control characters in name")
    func sanitizesControlChars() {
        let cleaned = SelectionPreset.sanitizedName("Pro\nject\u{0}X")
        #expect(!cleaned.contains("\n"))
        #expect(!cleaned.contains("\u{0}"))
    }

    @Test("Trims whitespace and caps length")
    func capsLength() {
        let longName = String(repeating: "a", count: 500)
        let cleaned = SelectionPreset.sanitizedName(longName)
        #expect(cleaned.count <= SelectionPreset.maxNameLength)
    }

    @Test("Empty or whitespace-only name sanitizes to empty (rejected upstream)")
    func emptyName() {
        #expect(SelectionPreset.sanitizedName("   ").isEmpty)
        #expect(SelectionPreset.sanitizedName("").isEmpty)
    }

    // MARK: — M-3: texto del toast de ausentes (accionable)

    @Test("missingFilesMessage is nil when nothing is missing")
    func missingMessageNone() {
        #expect(SelectionPreset.missingFilesMessage(missingPaths: []) == nil)
    }

    @Test("missingFilesMessage names a single missing file")
    func missingMessageOne() {
        #expect(SelectionPreset.missingFilesMessage(missingPaths: ["notas.md"]) == "'notas.md' not found")
    }

    @Test("missingFilesMessage names one and counts the rest")
    func missingMessageMany() {
        let message = SelectionPreset.missingFilesMessage(missingPaths: ["notas.md", "spec.md", "x.md"])
        #expect(message == "'notas.md' and 2 more not found")
    }

    @Test("Upsert caps total number of presets (SEC-8)")
    func capsCount() {
        let defaults = makeIsolatedDefaults()
        for i in 0..<(SelectionPresetStore.maxPresets + 10) {
            SelectionPresetStore.upsert(SelectionPreset(name: "P\(i)", relativePaths: ["f.md"]), in: defaults)
        }
        #expect(SelectionPresetStore.load(from: defaults).count <= SelectionPresetStore.maxPresets)
    }
}
