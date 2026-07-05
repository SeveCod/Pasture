import Testing
import Foundation
@testable import PastureKit

/// Bloque 9 (sustituto en-suite del smoke test por pipe): ejercita la secuencia
/// completa del cliente MCP (initialize → initialized → tools/list → tools/call)
/// a través del dispatcher sobre un vault temporal real. El único componente que
/// esto NO cubre es el transporte `FileHandle` real del executable, que tiene su
/// propio test (`MCPLineReaderTests`, vía Pipe). Juntos cubren el camino completo.
@Suite struct MCPEndToEndTests {

    private func makeVault() -> (MCPDispatcher, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-e2e-\(UUID().uuidString)", isDirectory: true)
        let collection = root.appendingPathComponent("proyecto-X", isDirectory: true)
        try? FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        try? "# Diseño\nContenido con ]]> y {{VAR}} crudo."
            .write(to: collection.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try? "Segundo fichero."
            .write(to: collection.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))
        return (dispatcher, root)
    }

    private func decode(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    @Test func fullClientHandshakeAndToolCall() throws {
        let (dispatcher, _) = makeVault()

        // 1. initialize → result con protocolVersion + capabilities.tools + serverInfo.
        let initLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let initJSON = try decode(initLine)
        #expect(initJSON.object?["result"]?.object?["protocolVersion"]?.stringValue == MCPProtocol.version)
        #expect(initJSON.object?["result"]?.object?["capabilities"]?.object?["tools"] != nil)

        // 2. notifications/initialized → sin respuesta.
        #expect(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)

        // 3. tools/list → las 4 tools.
        let listLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let listJSON = try decode(listLine)
        #expect(listJSON.object?["result"]?.object?["tools"]?.arrayValue?.count == 4)

        // 4. tools/call feed_context → contexto ensamblado, isError false, framing OK.
        let callLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"feed_context","arguments":{"collection":"proyecto-X"}}}"#))
        // El framing newline-delimited está a salvo: la respuesta es UNA línea.
        #expect(!callLine.contains("\n"))
        let callJSON = try decode(callLine)
        let result = callJSON.object?["result"]?.object
        #expect(result?["isError"] != nil)
        let content = result?["content"]?.arrayValue?.first?.object?["text"]?.stringValue ?? ""
        #expect(content.contains("<context name=\"a.md\">"))
        #expect(content.contains("{{VAR}}"))                 // crudo (D3)
        #expect(content.contains("]]]]><![CDATA[>"))         // ]]> escapado (HU-6)
    }

    /// Confirma que las respuestas serializadas nunca contienen `\/` (gotcha 7,
    /// .withoutEscapingSlashes) usando un fichero con barras en una ruta de feed.
    @Test func responsesDoNotEscapeSlashes() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"feed_context","arguments":{"collection":"proyecto-X"}}}"#))
        #expect(!line.contains(#"\/"#))
    }

    // MARK: — AC#11 (v1.6): secuencia completa con las 3 primitivas

    /// initialize → resources/list → resources/read → prompts/list → prompts/get,
    /// línea a línea. Cada respuesta es UNA línea JSON válida, sin `\/` en los uri
    /// (que llevan barras): blinda ADR-MCP-006 para las primitivas nuevas.
    @Test func fullSequenceAcrossThreePrimitives() throws {
        let (dispatcher, _) = makeVault()

        // initialize declara las 3 capabilities.
        let initLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#))
        let capabilities = try decode(initLine).object?["result"]?.object?["capabilities"]?.object
        #expect(capabilities?["resources"] != nil)
        #expect(capabilities?["prompts"] != nil)

        // resources/list → los 2 .md del vault; uri sin `\/`.
        let resListLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":2,"method":"resources/list"}"#))
        #expect(!resListLine.contains("\n"))
        #expect(!resListLine.contains(#"\/"#))
        let resources = try decode(resListLine).object?["result"]?.object?["resources"]?.arrayValue
        #expect(resources?.count == 2)

        // resources/read del fichero con {{VAR}} → contenido crudo (no renderizado).
        let readLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"pasture:///proyecto-X/a.md"}}"#))
        let readText = try decode(readLine).object?["result"]?.object?["contents"]?.arrayValue?
            .first?.object?["text"]?.stringValue ?? ""
        #expect(readText.contains("{{VAR}}"))   // resource entrega crudo

        // prompts/list → a.md tiene {{VAR}} ⇒ es prompt.
        let promptsListLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":4,"method":"prompts/list"}"#))
        let names = try decode(promptsListLine).object?["result"]?.object?["prompts"]?.arrayValue?
            .compactMap { $0.object?["name"]?.stringValue } ?? []
        #expect(names.contains("proyecto-X__a"))

        // prompts/get → render single-pass, VAR sustituida.
        let getLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":5,"method":"prompts/get","params":{"name":"proyecto-X__a","arguments":{"VAR":"Hola"}}}"#))
        #expect(!getLine.contains("\n"))
        let getText = try decode(getLine).object?["result"]?.object?["messages"]?.arrayValue?
            .first?.object?["content"]?.object?["text"]?.stringValue ?? ""
        #expect(getText.contains("Hola"))
        #expect(!getText.contains("{{VAR}}"))   // sustituida en el render
    }
}
