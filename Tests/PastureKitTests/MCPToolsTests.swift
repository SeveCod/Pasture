import Testing
import Foundation
@testable import PastureKit

/// Bloques 3-7 del diseño: las cuatro tools. Cada test crea un vault temporal
/// real para ejercitar FileLibrary/PathValidator/ContextBuilder sin mocks.
@Suite struct MCPToolsTests {

    // MARK: — Helpers de vault temporal

    /// Crea un vault temporal vacío y devuelve (config, root). El llamante
    /// puebla el vault con `write`.
    private func makeVault(format: FeedFormat = .xml) -> (MCPServerConfig, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-tools-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (MCPServerConfig(vaultRoot: root, feedFormat: format), root)
    }

    private func write(_ content: String, to relativePath: String, in root: URL) {
        let url = root.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Texto concatenado de los `content` del resultado.
    private func text(_ result: ToolCallResult) -> String {
        result.content.map(\.text).joined(separator: "\n")
    }

    // MARK: — Bloque 3: tools/list (gotcha 4)

    @Test func catalogExposesFourTools() {
        let names = MCPTools.catalog().tools.map(\.name)
        #expect(names.sorted() == ["feed_context", "list_files", "read_file", "search"])
    }

    @Test func everyToolHasObjectInputSchema() throws {
        // Serializamos y verificamos que cada inputSchema tiene type:"object".
        let line = try MCPTools.catalog().mcpLine()
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
        let tools = try #require(json.object?["tools"]?.arrayValue)
        #expect(tools.count == 4)
        for tool in tools {
            #expect(tool.object?["inputSchema"]?.object?["type"]?.stringValue == "object")
        }
    }

    @Test func feedContextDeclaresCollectionAndFiles() {
        let feed = MCPTools.catalog().tools.first { $0.name == "feed_context" }
        let props = feed?.inputSchema.properties
        #expect(props?["collection"] != nil)
        #expect(props?["files"] != nil)
        #expect(props?["files"]?.type == "array")
    }

    // MARK: — Bloque 4: read_file (SEC-M1, SEC-M2 — bloque de seguridad)

    /// Construye los `arguments` de una tools/call para invocar `run`.
    private func callArgs(_ args: [String: JSONValue]) -> JSONValue {
        .object(args)
    }

    @Test func readFileReturnsRawContent() {
        let (config, root) = makeVault()
        write("# Diseño\n{{VAR}} sin renderizar", to: "proyecto-X/diseno.md", in: root)
        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("proyecto-X/diseno.md")]), config: config)
        #expect(!result.isError)
        #expect(text(result).contains("# Diseño"))
        #expect(text(result).contains("{{VAR}}"))   // crudo (D3)
    }

    @Test func readFileRejectsRelativeTraversal() {
        let (config, root) = makeVault()
        // Fichero sensible FUERA del vault, en el padre del root.
        let outside = root.deletingLastPathComponent().appendingPathComponent("secret-outside.txt")
        try? "TOP SECRET".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("../secret-outside.txt")]), config: config)
        #expect(result.isError)
        #expect(!text(result).contains("TOP SECRET"))
    }

    @Test func readFileRejectsDeepTraversal() {
        let (config, _) = makeVault()
        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("../../../../etc/passwd")]), config: config)
        #expect(result.isError)
        #expect(!text(result).contains("root:"))
    }

    @Test func readFileRejectsAbsolutePath() {
        let (config, _) = makeVault()
        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("/etc/passwd")]), config: config)
        #expect(result.isError)
        #expect(!text(result).contains("root:"))
    }

    /// SEC-M2: un symlink REAL dentro del vault que apunta fuera no debe filtrar
    /// el destino. PathValidator no resuelve symlinks; la capa MCP sí.
    @Test func readFileRejectsSymlinkEscapingVault() {
        let (config, root) = makeVault()
        // Fichero sensible fuera del vault.
        let outside = root.deletingLastPathComponent().appendingPathComponent("id_rsa-\(UUID().uuidString)")
        try? "PRIVATE KEY MATERIAL".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        // Symlink dentro del vault apuntando al fichero de fuera.
        let link = root.appendingPathComponent("inocente.md")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("inocente.md")]), config: config)
        #expect(result.isError)
        #expect(!text(result).contains("PRIVATE KEY MATERIAL"))
    }

    @Test func readFileMissingFileIsToolError() {
        let (config, _) = makeVault()
        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("no-existe.md")]), config: config)
        #expect(result.isError)
    }

    @Test func readFileMissingPathArgumentIsToolError() {
        let (config, _) = makeVault()
        let result = MCPTools.readFile(arguments: callArgs([:]), config: config)
        #expect(result.isError)
    }

    /// SEC-M8 (D4): un fichero con un secreto se entrega ÍNTEGRO + warning
    /// enmascarado (familia + fichero), nunca el valor, y NO isError.
    @Test func readFileAttachesSecretWarningWithoutBlocking() {
        let (config, root) = makeVault()
        write("api key: sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWX", to: "leak.md", in: root)
        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("leak.md")]), config: config)
        #expect(!result.isError)
        // Contenido íntegro.
        #expect(text(result).contains("sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWX"))
        // Warning presente, con la familia, SIN el valor completo.
        let warning = try? #require(result.warning)
        #expect(warning?.contains("Anthropic key") == true)
        #expect(warning?.contains("leak.md") == true)
        #expect(warning?.contains("sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWX") == false)
    }

    /// SEC-M5: una respuesta que excedería el límite → isError, sin serializar el gigante.
    @Test func readFileTooLargeIsToolError() {
        let (config, root) = makeVault()
        let huge = String(repeating: "A", count: MCPLimits.maxResponseBytes + 1)
        write(huge, to: "huge.md", in: root)
        let result = MCPTools.readFile(
            arguments: callArgs(["path": .string("huge.md")]), config: config)
        #expect(result.isError)
        #expect(text(result).localizedCaseInsensitiveContains("grande"))
    }

    // MARK: — Bloque 5: list_files (HU-8)

    @Test func listFilesReportsPathsAndCollections() {
        let (config, root) = makeVault()
        write("raiz", to: "root1.md", in: root)
        write("raiz2", to: "root2.md", in: root)
        write("p1", to: "proyecto-X/a.md", in: root)
        write("p2", to: "proyecto-X/b.md", in: root)
        write("n1", to: "notas/c.md", in: root)

        let result = MCPTools.listFiles(config: config)
        #expect(!result.isError)
        let out = text(result)
        // Rutas relativas presentes.
        #expect(out.contains("root1.md"))
        #expect(out.contains("proyecto-X/a.md"))
        #expect(out.contains("notas/c.md"))
        // Nombre de colección asociado.
        #expect(out.contains("proyecto-X"))
        #expect(out.contains("notas"))
    }

    @Test func listFilesExcludesHiddenAndSymlinks() {
        let (config, root) = makeVault()
        write("visible", to: "visible.md", in: root)
        write("oculto", to: ".hidden.md", in: root)
        // Symlink a un .md externo.
        let outside = root.deletingLastPathComponent().appendingPathComponent("ext-\(UUID().uuidString).md")
        try? "external".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = root.appendingPathComponent("linked.md")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let result = MCPTools.listFiles(config: config)
        let out = text(result)
        #expect(out.contains("visible.md"))
        #expect(!out.contains(".hidden.md"))
        #expect(!out.contains("linked.md"))
    }

    @Test func listFilesEmptyVaultSucceeds() {
        let (config, _) = makeVault()
        let result = MCPTools.listFiles(config: config)
        #expect(!result.isError)   // vault vacío es un estado válido, no un error
    }

    // MARK: — Bloque 6: search (HU-10, D1, SEC-M4)

    @Test func searchFindsLiteralMatchesCaseInsensitive() {
        let (config, root) = makeVault()
        write("notes about Deployment pipeline", to: "a.md", in: root)
        write("more DEPLOYMENT steps", to: "b.md", in: root)
        write("unrelated content", to: "c.md", in: root)

        let result = MCPTools.search(
            arguments: callArgs(["query": .string("deployment")]), config: config)
        #expect(!result.isError)
        let out = text(result)
        #expect(out.contains("a.md"))
        #expect(out.contains("b.md"))
        #expect(!out.contains("c.md"))
    }

    /// HU-10: query vacía NO debe volcar el vault entero, aunque MDFile.matches
    /// devuelva true para query vacía. La tool intercepta antes.
    @Test func searchEmptyQueryReturnsEmptyNotWholeVault() {
        let (config, root) = makeVault()
        write("file one", to: "a.md", in: root)
        write("file two", to: "b.md", in: root)
        let result = MCPTools.search(
            arguments: callArgs(["query": .string("")]), config: config)
        #expect(!result.isError)
        let out = text(result)
        #expect(!out.contains("a.md"))
        #expect(!out.contains("b.md"))
    }

    /// D1 / SEC-M4: una query patológica para regex se trata como literal (sin ReDoS).
    @Test func searchTreatsRegexMetacharsAsLiteral() {
        let (config, root) = makeVault()
        write("contains (a+)+$ literally", to: "a.md", in: root)
        write("no match here", to: "b.md", in: root)
        let result = MCPTools.search(
            arguments: callArgs(["query": .string("(a+)+$")]), config: config)
        #expect(!result.isError)
        // El que contiene la cadena literal casa; el otro no.
        #expect(text(result).contains("a.md"))
    }

    /// SEC-M4: query > 1000 caracteres → isError.
    @Test func searchRejectsOverlongQuery() {
        let (config, _) = makeVault()
        let longQuery = String(repeating: "x", count: MCPLimits.maxQueryLength + 1)
        let result = MCPTools.search(
            arguments: callArgs(["query": .string(longQuery)]), config: config)
        #expect(result.isError)
    }

    /// SEC-M4: el resultado se acota a maxSearchResults.
    @Test func searchCapsResultCount() {
        let (config, root) = makeVault()
        for index in 0..<(MCPLimits.maxSearchResults + 20) {
            write("token present here", to: "f\(index).md", in: root)
        }
        let result = MCPTools.search(
            arguments: callArgs(["query": .string("token")]), config: config)
        #expect(!result.isError)
        // Cuenta de rutas .md en la salida no supera el cap.
        let matchCount = text(result).components(separatedBy: ".md").count - 1
        #expect(matchCount <= MCPLimits.maxSearchResults)
    }

    // MARK: — Bloque 7: feed_context (tool estrella, HU-6/7, D2/D3, SEC-M6)

    /// SEC-M6 / métrica del PRD: la salida de feed_context para una colección es
    /// ESTRUCTURALMENTE IDÉNTICA al Feed que la app produce (mismo ContextBuilder).
    @Test func feedContextCollectionMatchesAppFeedGolden() {
        let (config, root) = makeVault(format: .xml)
        write("aaa", to: "proyecto-X/a.md", in: root)
        write("bbb", to: "proyecto-X/b.md", in: root)

        let result = MCPTools.feedContext(
            arguments: callArgs(["collection": .string("proyecto-X")]), config: config)
        #expect(!result.isError)

        // Golden: lo que la app produciría con la misma selección y formato.
        // El orden de mdFiles dentro de una colección lo fija FileLibrary; lo
        // replicamos para construir el esperado en el MISMO orden.
        let expectedFiles = FileLibrary.mdFiles(in: root.appendingPathComponent("proyecto-X"))
            .map { ContextBuilder.FileEntry(name: $0.name, content: $0.content) }
        let golden = ContextBuilder.build(files: expectedFiles, format: .xml)
        #expect(text(result) == golden)
    }

    /// HU-6: secuencia de cierre CDATA escapada (sin inyección).
    @Test func feedContextEscapesCDATAClosing() {
        let (config, root) = makeVault(format: .xml)
        write("before ]]> after", to: "proyecto-X/tricky.md", in: root)
        let result = MCPTools.feedContext(
            arguments: callArgs(["collection": .string("proyecto-X")]), config: config)
        #expect(!result.isError)
        #expect(!text(result).contains("before ]]> after"))
        #expect(text(result).contains("]]]]><![CDATA[>"))
    }

    /// HU-6: colección inexistente → isError, conexión viva.
    @Test func feedContextUnknownCollectionIsToolError() {
        let (config, _) = makeVault()
        let result = MCPTools.feedContext(
            arguments: callArgs(["collection": .string("fantasma")]), config: config)
        #expect(result.isError)
        #expect(text(result).localizedCaseInsensitiveContains("colección")
            || text(result).localizedCaseInsensitiveContains("collection"))
    }

    /// HU-7: lista de ficheros ensamblada EN EL ORDEN pedido.
    @Test func feedContextFileListPreservesOrder() {
        let (config, root) = makeVault(format: .xml)
        write("contenido a", to: "a.md", in: root)
        write("contenido b", to: "notas/b.md", in: root)

        let result = MCPTools.feedContext(
            arguments: callArgs(["files": .array([.string("notas/b.md"), .string("a.md")])]),
            config: config)
        #expect(!result.isError)
        let out = text(result)
        let bPos = out.range(of: "b.md")!.lowerBound
        let aPos = out.range(of: "a.md")!.lowerBound
        #expect(bPos < aPos)   // orden pedido: b antes que a
    }

    /// HU-7: un fichero ausente se OMITE + aviso; NO falla en bloque.
    @Test func feedContextMissingFileOmittedWithNotice() {
        let (config, root) = makeVault(format: .xml)
        write("real", to: "a.md", in: root)
        let result = MCPTools.feedContext(
            arguments: callArgs(["files": .array([.string("a.md"), .string("fantasma.md")])]),
            config: config)
        #expect(!result.isError)
        #expect(text(result).contains("real"))           // el que existe se ensambla
        #expect((result.warning ?? "").contains("fantasma.md")
            || text(result).contains("fantasma.md"))     // aviso del ausente
    }

    /// HU-7: ni collection ni files → isError.
    @Test func feedContextNoSelectorIsToolError() {
        let (config, _) = makeVault()
        let result = MCPTools.feedContext(arguments: callArgs([:]), config: config)
        #expect(result.isError)
    }

    /// D2: si se pasan ambos, gana la lista de ficheros (más específica).
    @Test func feedContextFilesWinsOverCollection() {
        let (config, root) = makeVault(format: .xml)
        write("solo a", to: "a.md", in: root)
        write("coleccion", to: "proyecto-X/c.md", in: root)
        let result = MCPTools.feedContext(
            arguments: callArgs([
                "collection": .string("proyecto-X"),
                "files": .array([.string("a.md")]),
            ]),
            config: config)
        #expect(!result.isError)
        #expect(text(result).contains("solo a"))
        #expect(!text(result).contains("coleccion"))
    }

    /// D3: templates servidos CRUDOS (los {{VAR}} se entregan sin renderizar).
    @Test func feedContextServesTemplatesRaw() {
        let (config, root) = makeVault(format: .xml)
        write("Hola {{NAME=Mundo}}, {{#if X}}sí{{/if}}", to: "proyecto-X/tpl.md", in: root)
        let result = MCPTools.feedContext(
            arguments: callArgs(["collection": .string("proyecto-X")]), config: config)
        #expect(!result.isError)
        #expect(text(result).contains("{{NAME=Mundo}}"))
        #expect(text(result).contains("{{#if X}}"))
    }

    /// SEC-M8 (D4): warning no bloqueante si un fichero del feed tiene secretos.
    @Test func feedContextAttachesSecretWarning() {
        let (config, root) = makeVault(format: .xml)
        write("key sk-ant-api03-ZYXWVUTSRQPONMLKJIHGFED", to: "proyecto-X/leak.md", in: root)
        let result = MCPTools.feedContext(
            arguments: callArgs(["collection": .string("proyecto-X")]), config: config)
        #expect(!result.isError)
        #expect(text(result).contains("sk-ant-api03-ZYXWVUTSRQPONMLKJIHGFED"))  // íntegro
        #expect((result.warning ?? "").contains("Anthropic key"))
        #expect((result.warning ?? "").contains("sk-ant-api03-ZYXWVUTSRQPONMLKJIHGFED") == false)
    }
}
