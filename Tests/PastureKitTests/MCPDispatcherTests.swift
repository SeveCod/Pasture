import Testing
import Foundation
@testable import PastureKit

/// Bloque 2 del diseño: ciclo de vida del dispatcher (initialize / initialized /
/// ping / método desconocido / JSON malformado). Frontera testeable sin pipes.
@Suite struct MCPDispatcherTests {

    /// Dispatcher con un vault temporal vacío (lifecycle no toca el FS).
    private func makeDispatcher() -> MCPDispatcher {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return MCPDispatcher(config: MCPServerConfig(vaultRoot: tmp, feedFormat: .xml))
    }

    /// Decodifica la línea de salida a un diccionario JSON genérico para aserciones.
    private func decode(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    // MARK: — initialize (gotcha 3: capabilities.tools presente)

    @Test func initializeEchoesProtocolVersionAndExposesTools() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        let result = json.object?["result"]?.object

        #expect(result?["protocolVersion"]?.stringValue == MCPProtocol.version)
        #expect(result?["serverInfo"]?.object?["name"]?.stringValue == "pasture-mcp")
        // capabilities.tools DEBE estar presente aunque vacío.
        let capabilities = result?["capabilities"]?.object
        #expect(capabilities?["tools"] != nil)
        #expect(capabilities?["tools"]?.object != nil)
    }

    @Test func initializeEchoesStringId() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":"req-7","method":"initialize","params":{}}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        #expect(json.object?["id"]?.stringValue == "req-7")
    }

    // MARK: — notificaciones (gotcha 5: sin respuesta)

    @Test func initializedNotificationProducesNoResponse() {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        #expect(dispatcher.handle(line: request) == nil)
    }

    @Test func emptyLineProducesNoResponse() {
        let dispatcher = makeDispatcher()
        #expect(dispatcher.handle(line: "") == nil)
    }

    // MARK: — ping

    @Test func pingReturnsEmptyResult() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":9,"method":"ping"}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        #expect(json.object?["id"]?.number != nil || json.object?["result"] != nil)
        #expect(json.object?["result"]?.object != nil)
    }

    // MARK: — método desconocido (-32601)

    @Test func unknownMethodReturnsMethodNotFound() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":5,"method":"does/not/exist"}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        #expect(json.object?["error"]?.object?["code"]?.number == Double(MCPProtocol.methodNotFound))
    }

    // MARK: — JSON malformado (-32700 con id null)

    @Test func malformedJSONReturnsParseErrorWithNullId() throws {
        let dispatcher = makeDispatcher()
        let response = try #require(dispatcher.handle(line: "{not json"))
        let json = try decode(response)
        #expect(json.object?["error"]?.object?["code"]?.number == Double(MCPProtocol.parseError))
        // id presente y null (parse error sin id correlacionable).
        if case .null = json.object?["id"] {
            // ok
        } else {
            Issue.record("id debería ser null en parse error")
        }
    }

    // MARK: — Integración dispatcher → tools (tools/list, tools/call)

    @Test func toolsListThroughDispatcher() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        let tools = try #require(json.object?["result"]?.object?["tools"]?.arrayValue)
        #expect(tools.count == 4)
    }

    /// SEC-M12: un tool/call con argumentos inválidos → isError dentro de result
    /// (no objeto error JSON-RPC), conexión viva.
    @Test func toolCallErrorIsIsErrorNotProtocolError() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"../../etc/passwd"}}}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        // Es result.isError, NO error JSON-RPC.
        #expect(json.object?["error"] == nil)
        #expect(json.object?["result"]?.object?["isError"] != nil)
    }

    // MARK: — H1: id:null explícito es un request inválido, NO una notificación

    /// Spec JSON-RPC 2.0: una notificación es un Request SIN el miembro `id`. Un
    /// Request con `id:null` presente NO es una notificación: hay que responderlo.
    /// Lo tratamos como invalid request (-32600) con `id:null`, no como silencio.
    @Test func explicitNullIdIsInvalidRequestNotNotification() throws {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","id":null,"method":"ping"}"#
        let response = try #require(dispatcher.handle(line: request))
        let json = try decode(response)
        #expect(json.object?["error"]?.object?["code"]?.number == Double(MCPProtocol.invalidRequest))
        // El id se ecoa como null explícito.
        if case .null = json.object?["id"] {
            // ok
        } else {
            Issue.record("id debería ecoarse como null para id:null explícito")
        }
    }

    /// Una notificación de verdad (sin el miembro `id`) sigue produciendo silencio.
    @Test func absentIdRemainsNotification() {
        let dispatcher = makeDispatcher()
        let request = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        #expect(dispatcher.handle(line: request) == nil)
    }

    // MARK: — H4: el campo `warning` (SEC-M8) llega en el JSON serializado

    /// El warning de SEC-M8 debe viajar en el JSON que ve el cliente, no solo en
    /// el objeto Swift. Verificación a través de handle(line:), end-to-end.
    @Test func secretWarningAppearsInSerializedJSON() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-warn-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let secretFile = tmp.appendingPathComponent("leak.md")
        try "key sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWX"
            .write(to: secretFile, atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: tmp, feedFormat: .xml))

        let request = #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"leak.md"}}}"#
        let response = try #require(dispatcher.handle(line: request))
        // La clave "warning" está presente en el JSON crudo.
        #expect(response.contains("\"warning\""))
        let json = try decode(response)
        let warning = json.object?["result"]?.object?["warning"]?.stringValue
        #expect(warning?.contains("Anthropic key") == true)
        // El valor del secreto NUNCA viaja en el warning (SEC-M8).
        #expect(warning?.contains("sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWX") == false)
    }

    /// Sin secretos, la clave `warning` se OMITE del JSON (Optional nil no serializa).
    @Test func noWarningKeyWhenContentClean() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-clean-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try "just clean notes"
            .write(to: tmp.appendingPathComponent("ok.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: tmp, feedFormat: .xml))

        let request = #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"ok.md"}}}"#
        let response = try #require(dispatcher.handle(line: request))
        #expect(!response.contains("\"warning\""))
    }

    // MARK: — SEC-M12: una request inválida NO tumba la conexión

    @Test func errorsDoNotThrow() {
        let dispatcher = makeDispatcher()
        // Ninguna de estas debe lanzar; todas devuelven una línea (o nil).
        _ = dispatcher.handle(line: "{not json")
        _ = dispatcher.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"unknown"}"#)
        _ = dispatcher.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        // Si llegamos aquí sin crash, la conexión sobrevive a entradas adversas.
        #expect(Bool(true))
    }
}

extension JSONValue {
    /// Accessor numérico de conveniencia para los tests.
    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
