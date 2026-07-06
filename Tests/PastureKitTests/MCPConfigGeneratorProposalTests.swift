import Testing
@testable import PastureKit

/// v1.8 Memory Inbox — los snippets de registro inyectan `PASTURE_ALLOW_PROPOSALS=1`
/// solo cuando el usuario activa el toggle; ausente cuando está desactivado.
@Suite("MCPConfigGenerator — allowProposals injection")
struct MCPConfigGeneratorProposalTests {

    private let bin = "/Applications/Pasture.app/Contents/MacOS/pasture-mcp"

    @Test("claude mcp add injects the env var when proposals are enabled")
    func claudeCodeInjectsWhenEnabled() {
        let cmd = MCPConfigGenerator.claudeCodeCommand(binaryPath: bin, feedFormat: .xml, allowProposals: true)
        #expect(cmd.contains("\(MCPServerConfig.allowProposalsEnvKey)=1"))
    }

    @Test("claude mcp add omits the env var when proposals are disabled")
    func claudeCodeOmitsWhenDisabled() {
        let cmd = MCPConfigGenerator.claudeCodeCommand(binaryPath: bin, feedFormat: .xml, allowProposals: false)
        #expect(!cmd.contains(MCPServerConfig.allowProposalsEnvKey))
    }

    @Test("desktop JSON injects the env var when proposals are enabled")
    func desktopJSONInjectsWhenEnabled() {
        let json = MCPConfigGenerator.claudeDesktopJSON(binaryPath: bin, feedFormat: .xml, allowProposals: true)
        #expect(json.contains(MCPServerConfig.allowProposalsEnvKey))
        #expect(json.contains("\"1\""))
    }

    @Test("desktop JSON omits the env var when proposals are disabled")
    func desktopJSONOmitsWhenDisabled() {
        let json = MCPConfigGenerator.claudeDesktopJSON(binaryPath: bin, feedFormat: .xml, allowProposals: false)
        #expect(!json.contains(MCPServerConfig.allowProposalsEnvKey))
    }
}
