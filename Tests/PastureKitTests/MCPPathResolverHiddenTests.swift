import Testing
import Foundation
@testable import PastureKit

/// v1.8 (revisión adversarial) — `MCPPathResolver` rechaza cualquier componente
/// oculto (empieza por `.`). Cierra a la vez la LECTURA de `.inbox/` por path
/// (`read_file`/`feed_context`/`resources/read`) y su uso como DESTINO de una
/// propuesta (`propose_note`/`propose_append`), alineándolo con la política de
/// ocultos que ya aplica `FileLibrary` a la enumeración.
@Suite("MCPPathResolver — hidden components")
struct MCPPathResolverHiddenTests {

    private let vault = URL(fileURLWithPath: "/tmp/vault")

    @Test("rejects a leading hidden component (.inbox)")
    func rejectsInbox() {
        #expect(MCPPathResolver.resolve(relativePath: ".inbox/x.md", vaultRoot: vault) == .failure(.outsideVault))
        #expect(MCPPathResolver.resolve(relativePath: ".inbox", vaultRoot: vault) == .failure(.outsideVault))
    }

    @Test("rejects a hidden component in any position")
    func rejectsNestedHidden() {
        #expect(MCPPathResolver.resolve(relativePath: "sub/.hidden.md", vaultRoot: vault) == .failure(.outsideVault))
        #expect(MCPPathResolver.resolve(relativePath: ".ssh/id_rsa", vaultRoot: vault) == .failure(.outsideVault))
    }

    @Test("still resolves a normal visible path")
    func resolvesNormal() {
        if case .failure = MCPPathResolver.resolve(relativePath: "notes/a.md", vaultRoot: vault) {
            Issue.record("a normal visible path must still resolve")
        }
        // Un punto que no es inicial de componente (extensión) es válido.
        if case .failure = MCPPathResolver.resolve(relativePath: "file.md", vaultRoot: vault) {
            Issue.record("a filename with an extension must still resolve")
        }
    }
}
