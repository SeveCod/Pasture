import Testing
import Foundation
@testable import PastureKit

/// v1.8 Memory Inbox — `allowProposals` habilita el camino de escritura del inbox.
/// Se lee de `PASTURE_ALLOW_PROPOSALS` (ADR-MCP-007: entorno, no UserDefaults).
/// Default `false` = regresión de solo-lectura idéntica a v1.7.
@Suite("MCPServerConfig — allowProposals")
struct MCPServerConfigTests {

    private let vault = URL(fileURLWithPath: "/tmp/vault")

    @Test("allowProposals defaults to false")
    func allowProposalsDefaultsToFalse() {
        let config = MCPServerConfig(vaultRoot: vault, feedFormat: .xml)
        #expect(config.allowProposals == false)
    }

    @Test("fromEnvironment enables proposals only when PASTURE_ALLOW_PROPOSALS is exactly \"1\"")
    func fromEnvironmentReadsAllowProposals() {
        let home = URL(fileURLWithPath: "/tmp/home")

        let on = MCPServerConfig.fromEnvironment(["PASTURE_ALLOW_PROPOSALS": "1"], homeDirectory: home)
        #expect(on.allowProposals == true)

        let absent = MCPServerConfig.fromEnvironment([:], homeDirectory: home)
        #expect(absent.allowProposals == false)

        let other = MCPServerConfig.fromEnvironment(["PASTURE_ALLOW_PROPOSALS": "true"], homeDirectory: home)
        #expect(other.allowProposals == false)
    }
}
