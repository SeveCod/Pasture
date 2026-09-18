import Testing
import Foundation
@testable import PastureKit

/// La versión del servidor MCP viaja en `serverInfo.version` del `initialize`.
///
/// Audit 360: este fichero fijaba el literal `"1.8.0"` con la app ya en 1.11.0,
/// de modo que **defendía el desfase** en vez de detectarlo — el caso de libro de
/// una guardia que mira al sitio equivocado. Ahora el contrato es relativo: la
/// versión del servidor debe coincidir con la del producto, que vive en
/// `scripts/bundle.sh` (fuente única, según el CLAUDE.md del repo).
@Suite("MCPProtocol — server version")
struct MCPServerVersionTests {

    /// Versión declarada en `scripts/bundle.sh`, leída del fichero real.
    private static func productVersion() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/PastureKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // raíz
        let script = try String(contentsOf: root.appendingPathComponent("scripts/bundle.sh"),
                                encoding: .utf8)
        for linea in script.split(separator: "\n") where linea.hasPrefix("VERSION=") {
            return linea
                .dropFirst("VERSION=".count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        throw VersionError.noVersionLine
    }

    private enum VersionError: Error { case noVersionLine }

    @Test("serverVersion va con la versión del producto (scripts/bundle.sh)")
    func serverVersionTracksProduct() throws {
        let esperada = try Self.productVersion()
        #expect(MCPProtocol.serverVersion == esperada, """
            El servidor MCP se distribuye dentro del bundle de la app: su versión \
            debe subir con ella. Si acabas de bumpear bundle.sh, sube también \
            MCPProtocol.serverVersion.
            """)
    }

    @Test("initialize expone esa misma versión en serverInfo")
    func initializeSurfacesVersion() throws {
        let esperada = try Self.productVersion()
        let line = try InitializeResult().mcpLine()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        #expect(json.object?["serverInfo"]?.object?["version"]?.stringValue == esperada)
    }
}
