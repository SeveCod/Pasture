import Testing
import Foundation
@testable import PastureKit

/// Context Compiler (v1.6) — CRUD de packs y retrocompatibilidad de presets (AC#7).
@Suite struct PackStoreTests {

    private func makePack(name: String = "pack", targets: Int = 1) -> CompilePack {
        let t = (0..<targets).map {
            CompileTarget(kind: .claudeMd, absolutePath: "/repo/\($0)/CLAUDE.md")
        }
        return CompilePack(name: name, presetID: UUID(), variables: ["PROJECT": "foo"], targets: t)
    }

    @Test func upsertInsertsThenUpdates() {
        let defaults = makeIsolatedUserDefaults()
        var pack = makePack(name: "a")
        PackStore.upsert(pack, in: defaults)
        #expect(PackStore.load(from: defaults).count == 1)

        pack.name = "renombrado"
        PackStore.upsert(pack, in: defaults)
        let loaded = PackStore.load(from: defaults)
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "renombrado")
    }

    @Test func deleteRemovesByID() {
        let defaults = makeIsolatedUserDefaults()
        let pack = makePack()
        PackStore.upsert(pack, in: defaults)
        PackStore.delete(id: pack.id, in: defaults)
        #expect(PackStore.load(from: defaults).isEmpty)
    }

    @Test func roundTripsVariablesAndTargets() throws {
        let defaults = makeIsolatedUserDefaults()
        let pack = makePack(name: "p", targets: 3)
        PackStore.upsert(pack, in: defaults)
        let loaded = try #require(PackStore.load(from: defaults).first)
        #expect(loaded.variables["PROJECT"] == "foo")
        #expect(loaded.targets.count == 3)
        #expect(loaded.presetID == pack.presetID)
    }

    @Test func capsPacksAtFifty() {
        let defaults = makeIsolatedUserDefaults()
        let packs = (0..<60).map { makePack(name: "p\($0)") }
        PackStore.save(packs, to: defaults)
        #expect(PackStore.load(from: defaults).count == PackStore.maxPacks)
    }

    @Test func capsTargetsAtTwentyPerPack() {
        let defaults = makeIsolatedUserDefaults()
        PackStore.save([makePack(name: "big", targets: 30)], to: defaults)
        let loaded = PackStore.load(from: defaults).first
        #expect(loaded?.targets.count == PackStore.maxTargetsPerPack)
    }

    // MARK: — AC#7: los presets v1.4/v1.5 decodifican sin pérdida

    @Test func legacyPresetsDecodeUnaffectedByPacks() throws {
        let defaults = makeIsolatedUserDefaults()
        // Fixture JSON del formato v1.4 de SelectionPreset (sin campos de pack).
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","name":"mi-preset","relativePaths":["a.md","sub/b.md"],"createdAt":0}]
        """
        defaults.set(Data(legacyJSON.utf8), forKey: "com.sevecod.pasture.selectionPresets")

        // Guardar packs NO toca la clave de presets.
        PackStore.upsert(makePack(), in: defaults)

        let presets = SelectionPresetStore.load(from: defaults)
        #expect(presets.count == 1)
        #expect(presets.first?.name == "mi-preset")
        #expect(presets.first?.relativePaths == ["a.md", "sub/b.md"])
    }
}
