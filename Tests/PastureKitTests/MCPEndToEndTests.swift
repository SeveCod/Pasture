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
}
