import Foundation
import Testing
@testable import PastureKit

/// Pliegue de las colecciones del sidebar. El invariante que más importa:
/// con búsqueda activa todo se ve abierto, pero el estado guardado NO se toca.
@Suite("CollectionExpansionStore")
struct CollectionExpansionStoreTests {

    /// Dominio propio por test para no contaminar `.standard`.
    private func freshDefaults() -> UserDefaults {
        let suite = "pasture.tests.expansion.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("Sin nada guardado, todo está plegado")
    func defaultsToCollapsed() {
        #expect(CollectionExpansionStore.load(from: freshDefaults()).isEmpty)
    }

    @Test("Lo guardado sobrevive a una relectura")
    func roundTrip() {
        let defaults = freshDefaults()
        CollectionExpansionStore.save(["c:Alpha", "u:"], to: defaults)
        #expect(CollectionExpansionStore.load(from: defaults) == ["c:Alpha", "u:"])
    }

    @Test("Sin búsqueda, manda el estado guardado")
    func storedWins() {
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: ["c:Alpha"], nodeID: "c:Alpha", isSearching: false) == true)
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: ["c:Alpha"], nodeID: "c:Beta", isSearching: false) == false)
    }

    @Test("Con búsqueda, todo se ve abierto aunque esté plegado")
    func searchForcesExpanded() {
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: [], nodeID: "c:Beta", isSearching: true) == true)
    }

    @Test("Con búsqueda, plegar o desplegar NO altera el estado guardado")
    func searchDoesNotWriteState() {
        let stored: Set<String> = ["c:Alpha"]
        #expect(CollectionExpansionStore.applying(
            false, to: stored, nodeID: "c:Alpha", isSearching: true) == stored)
        #expect(CollectionExpansionStore.applying(
            true, to: stored, nodeID: "c:Beta", isSearching: true) == stored)
    }

    @Test("Sin búsqueda, desplegar añade y plegar quita")
    func togglesWhenNotSearching() {
        #expect(CollectionExpansionStore.applying(
            true, to: [], nodeID: "c:Alpha", isSearching: false) == ["c:Alpha"])
        #expect(CollectionExpansionStore.applying(
            false, to: ["c:Alpha"], nodeID: "c:Alpha", isSearching: false) == [])
    }

    @Test("Una colección borrada del disco deja una entrada huérfana inofensiva")
    func orphanEntryIsHarmless() {
        let stored: Set<String> = ["c:Borrada"]
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: stored, nodeID: "c:Viva", isSearching: false) == false)
    }
}
