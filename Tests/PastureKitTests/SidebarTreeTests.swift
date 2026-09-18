import Foundation
import Testing
@testable import PastureKit

/// Agrupación del sidebar en nodos plegables. Lógica pura: `build` no ordena,
/// preserva el orden que le entregan y solo agrupa.
@Suite("SidebarTree")
struct SidebarTreeTests {

    private let base = URL(fileURLWithPath: "/tmp/pasture-test", isDirectory: true)

    /// Fichero de prueba en la raíz (colección nil) o dentro de `collection`.
    private func file(_ name: String, in collection: String? = nil, tokens: Int = 10) -> MDFile {
        var url = base
        if let collection { url.appendPathComponent(collection, isDirectory: true) }
        url.appendPathComponent("\(name).md")
        return MDFile(
            name: name, url: url, modifiedDate: Date(),
            content: "", tokens: tokens, hasTemplateVars: false
        )
    }

    @Test("Uncategorized va el primero")
    func uncategorizedFirst() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Zeta"), file("b")],
            collections: ["Zeta"], base: base
        )
        #expect(nodes.first?.isUncategorized == true)
        #expect(nodes.first?.name == nil)
    }

    @Test("Uncategorized no aparece si no hay ficheros sueltos")
    func uncategorizedOmittedWhenEmpty() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Zeta")],
            collections: ["Zeta"], base: base
        )
        #expect(nodes.count == 1)
        #expect(nodes.first?.name == "Zeta")
    }

    @Test("Cada fichero cae en su colección")
    func groupsByCollection() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Alpha"), file("b", in: "Beta"), file("c", in: "Alpha")],
            collections: ["Alpha", "Beta"], base: base
        )
        #expect(nodes.count == 2)
        #expect(nodes[0].files.map(\.name) == ["a", "c"])
        #expect(nodes[1].files.map(\.name) == ["b"])
    }

    @Test("Respeta el orden de `collections` que recibe")
    func preservesCollectionOrder() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Zeta"), file("b", in: "Alpha")],
            collections: ["Alpha", "Zeta"], base: base
        )
        #expect(nodes.map(\.name) == ["Alpha", "Zeta"])
    }

    @Test("Preserva el orden de los ficheros dentro del nodo (no reordena)")
    func preservesFileOrder() {
        let nodes = SidebarTree.build(
            files: [file("zzz", in: "Alpha"), file("aaa", in: "Alpha")],
            collections: ["Alpha"], base: base
        )
        #expect(nodes[0].files.map(\.name) == ["zzz", "aaa"])
    }

    @Test("Una colección vacía sigue apareciendo (es la única vía de borrarla)")
    func emptyCollectionStillShows() {
        let nodes = SidebarTree.build(files: [], collections: ["Vacia"], base: base)
        #expect(nodes.count == 1)
        #expect(nodes[0].fileCount == 0)
    }

    @Test("hidingEmpty descarta las colecciones sin ficheros (modo búsqueda)")
    func hidingEmptyDropsEmpties() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Alpha")],
            collections: ["Alpha", "Vacia"], base: base, hidingEmpty: true
        )
        #expect(nodes.map(\.name) == ["Alpha"])
    }

    @Test("fileCount y totalTokens se calculan por nodo")
    func countsAndTokens() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Alpha", tokens: 100), file("b", in: "Alpha", tokens: 25)],
            collections: ["Alpha"], base: base
        )
        #expect(nodes[0].fileCount == 2)
        #expect(nodes[0].totalTokens == 125)
    }

    @Test("El id distingue Uncategorized de una colección de nombre vacío")
    func idDisambiguates() {
        let nodes = SidebarTree.build(
            files: [file("a")],
            collections: [""], base: base
        )
        #expect(Set(nodes.map(\.id)).count == nodes.count)
        #expect(nodes.first(where: { $0.isUncategorized })?.id == "u:")
    }

    /// Audit 360: este contrato estaba SIN vigilar. El test de arriba solo exigía
    /// que los ids fuesen distintos entre sí y fijaba `"u:"`, así que cambiar el
    /// prefijo `"c:"` dejaba la suite entera en verde (comprobado por mutación).
    /// Importa porque el id es la clave persistida en `CollectionExpansionStore`
    /// y la usa también el auto-despliegue del sidebar: si deriva, el estado de
    /// plegado del usuario se huerfaniza y la nota activa queda invisible.
    @Test("Los prefijos del id son parte del contrato, no un detalle")
    func idPrefixesAreContractual() {
        #expect(CollectionNode.id(forCollection: nil) == "u:")
        #expect(CollectionNode.id(forCollection: "Mercados") == "c:Mercados")
        #expect(CollectionNode.id(forCollection: "") == "c:")
        // Y el nodo construido debe coincidir con la fuente única: si `id` y el
        // helper estático divergen, la GUI y el store dejan de entenderse.
        let node = CollectionNode(name: "Mercados", files: [])
        #expect(node.id == CollectionNode.id(forCollection: "Mercados"))
        #expect(CollectionNode(name: nil, files: []).id == CollectionNode.id(forCollection: nil))
    }

    @Test("Hashable/Equatable se basan solo en id, no en (name, files)")
    func equatableByIdentityOnly() {
        let a = CollectionNode(name: "Alpha", files: [file("a", in: "Alpha")])
        let b = CollectionNode(name: "Alpha", files: [file("b", in: "Alpha"), file("c", in: "Alpha")])
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
