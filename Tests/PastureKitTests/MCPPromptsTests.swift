import Testing
import Foundation
@testable import PastureKit

/// Primitiva MCP `prompts` (v1.6): cada template del vault como prompt
/// parametrizado. Ejercitado vía `MCPDispatcher.handle(line:)` (sin spawn).
/// Invariantes: solo lectura (SEC-M11), render single-pass (no re-parseo de
/// valores), guard de secretos post-sustitución (ADR-QW-002 / SEC-M8).
@Suite struct MCPPromptsTests {

    // MARK: — Fixture

    private func makeVault() -> (MCPDispatcher, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-prompts-\(UUID().uuidString)", isDirectory: true)
        let collection = root.appendingPathComponent("proyecto", isDirectory: true)
        try? FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        // Sin variables → NO es prompt (AC#6).
        try? "Solo texto, sin variables."
            .write(to: root.appendingPathComponent("plain.md"), atomically: true, encoding: .utf8)
        // Escalar con y sin default.
        try? "Hola {{NOMBRE}}, tono {{TONO=formal}}."
            .write(to: root.appendingPathComponent("greeting.md"), atomically: true, encoding: .utf8)
        // Escalar + default + lista (#each).
        try? "{{NOMBRE}} {{TONO=formal}} {{#each ITEMS}}{{.}} {{/each}}"
            .write(to: collection.appendingPathComponent("full.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))
        return (dispatcher, root)
    }

    private func decode(_ line: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
    }

    private func prompt(named name: String, in json: JSONValue) -> JSONValue? {
        json.object?["result"]?.object?["prompts"]?.arrayValue?
            .first { $0.object?["name"]?.stringValue == name }
    }

    // MARK: — AC#6: solo templates aparecen

    @Test func listExcludesFilesWithoutVariables() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":1,"method":"prompts/list"}"#))
        let json = try decode(line)
        let names = Set(json.object?["result"]?.object?["prompts"]?.arrayValue?
            .compactMap { $0.object?["name"]?.stringValue } ?? [])
        #expect(names == ["greeting", "proyecto__full"])
        #expect(!names.contains("plain"))
    }

    // MARK: — AC#7: argumentos tipados (required / default / lista)

    @Test func listDeclaresTypedArguments() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":2,"method":"prompts/list"}"#))
        let json = try decode(line)
        let full = try #require(prompt(named: "proyecto__full", in: json))
        let args = try #require(full.object?["arguments"]?.arrayValue)
        #expect(args.count == 3)

        func arg(_ name: String) -> [String: JSONValue]? {
            args.first { $0.object?["name"]?.stringValue == name }?.object
        }
        // NOMBRE: required, sin default.
        #expect(arg("NOMBRE")?["required"] != nil)
        let nombreLine = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":3,"method":"prompts/list"}"#))
        #expect(nombreLine.contains("\"required\":true") || nombreLine.contains("required"))

        // TONO: opcional, default 'formal' citado en description.
        let tono = try #require(arg("TONO"))
        #expect(tono["description"]?.stringValue?.contains("formal") == true)

        // ITEMS: lista, description documenta la convención de comas.
        let items = try #require(arg("ITEMS"))
        #expect(items["description"]?.stringValue?.lowercased().contains("comma-separated") == true)
    }

    /// Verificación fina de required=true/false por decodificación directa.
    @Test func requiredFlagReflectsDefaultPresence() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":4,"method":"prompts/list"}"#))
        let json = try decode(line)
        let full = try #require(prompt(named: "proyecto__full", in: json))
        let args = try #require(full.object?["arguments"]?.arrayValue)
        func required(_ name: String) -> Bool? {
            let obj = args.first { $0.object?["name"]?.stringValue == name }?.object
            if case .bool(let b)? = obj?["required"] { return b }
            return nil
        }
        #expect(required("NOMBRE") == true)   // sin default
        #expect(required("TONO") == false)    // con default
        #expect(required("ITEMS") == true)    // lista, sin default
    }

    // MARK: — AC#8: get render single-pass + default + no re-parseo

    @Test func getRendersSinglePassResolvingDefaults() throws {
        let (dispatcher, _) = makeVault()
        // NOMBRE lleva {{OTRA}} embebido; TONO vacío → default 'formal'.
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":5,"method":"prompts/get","params":{"name":"greeting","arguments":{"NOMBRE":"Ana {{OTRA}}","TONO":""}}}"#))
        let json = try decode(line)
        let messages = try #require(json.object?["result"]?.object?["messages"]?.arrayValue)
        #expect(messages.count == 1)
        #expect(messages.first?.object?["role"]?.stringValue == "user")
        let text = try #require(messages.first?.object?["content"]?.object?["text"]?.stringValue)
        #expect(text == "Hola Ana {{OTRA}}, tono formal.")
        // {{OTRA}} sigue literal: no se re-interpretó como variable (single-pass).
        #expect(text.contains("{{OTRA}}"))
    }

    @Test func getSubstitutesListVariable() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":6,"method":"prompts/get","params":{"name":"proyecto__full","arguments":{"NOMBRE":"X","ITEMS":"a,b,c"}}}"#))
        let json = try decode(line)
        let text = try #require(json.object?["result"]?.object?["messages"]?.arrayValue?
            .first?.object?["content"]?.object?["text"]?.stringValue)
        #expect(text == "X formal a b c ")
    }

    // MARK: — AC#10: errores de PROTOCOLO (-32602)

    @Test func getUnknownPromptIsProtocolError() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":7,"method":"prompts/get","params":{"name":"nope","arguments":{}}}"#))
        let json = try decode(line)
        let error = try #require(json.object?["error"]?.object)
        #expect(error["code"] != nil)
        #expect(json.object?["result"] == nil)
    }

    @Test func getMissingRequiredArgumentIsProtocolError() throws {
        let (dispatcher, _) = makeVault()
        // greeting requiere NOMBRE; se omite.
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":8,"method":"prompts/get","params":{"name":"greeting","arguments":{"TONO":"casual"}}}"#))
        let json = try decode(line)
        #expect(json.object?["error"] != nil)
        let msg = json.object?["error"]?.object?["message"]?.stringValue ?? ""
        #expect(msg.contains("NOMBRE"))
    }

    // MARK: — AC#9: secreto post-render enmascarado en description

    @Test func getMasksSecretInDescriptionButDeliversContent() throws {
        let (dispatcher, root) = makeVault()
        // Fixture de clave por CONCATENACIÓN (Push Protection).
        let syntheticKey = "sk-ant-" + "api03-" + "abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        try? "Clave: {{SECRET}}"
            .write(to: root.appendingPathComponent("leak.md"), atomically: true, encoding: .utf8)

        let requestLine = #"{"jsonrpc":"2.0","id":9,"method":"prompts/get","params":{"name":"leak","arguments":{"SECRET":"\#(syntheticKey)"}}}"#
        let line = try #require(dispatcher.handle(line: requestLine))
        let json = try decode(line)
        let result = try #require(json.object?["result"]?.object)

        // Contenido entregado ÍNTEGRO (el secreto está en el mensaje renderizado).
        let text = try #require(result["messages"]?.arrayValue?.first?.object?["content"]?.object?["text"]?.stringValue)
        #expect(text == "Clave: \(syntheticKey)")

        // description lleva el aviso enmascarado (familia + fichero), SIN el valor.
        let description = try #require(result["description"]?.stringValue)
        #expect(description.contains("secrets") || description.contains("Anthropic"))
        #expect(!description.contains(syntheticKey))
    }

    @Test func getCleanPromptHasNoSecretWarning() throws {
        let (dispatcher, _) = makeVault()
        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":10,"method":"prompts/get","params":{"name":"greeting","arguments":{"NOMBRE":"Ana"}}}"#))
        let json = try decode(line)
        // Sin secreto → description ausente (Encodable omite nil).
        #expect(json.object?["result"]?.object?["description"] == nil)
    }

    // MARK: — Cap de longitud de argumento (SEC-M13)

    @Test func getRejectsOversizedArgument() throws {
        let (dispatcher, _) = makeVault()
        let huge = String(repeating: "x", count: MCPLimits.maxPromptArgumentLength + 1)
        let requestLine = #"{"jsonrpc":"2.0","id":11,"method":"prompts/get","params":{"name":"greeting","arguments":{"NOMBRE":"\#(huge)"}}}"#
        let line = try #require(dispatcher.handle(line: requestLine))
        let json = try decode(line)
        #expect(json.object?["error"] != nil)
    }

    // MARK: — Colisión de nombres (criterio técnico)

    @Test func nameCollisionDropsSecondPrompt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasture-mcp-collision-\(UUID().uuidString)", isDirectory: true)
        let sub = root.appendingPathComponent("a", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        // "a__b.md" en raíz y "a/b.md" en colección → ambos mapean a "a__b".
        try? "root {{V}}".write(to: root.appendingPathComponent("a__b.md"), atomically: true, encoding: .utf8)
        try? "coll {{V}}".write(to: sub.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let dispatcher = MCPDispatcher(config: MCPServerConfig(vaultRoot: root, feedFormat: .xml))

        let line = try #require(dispatcher.handle(
            line: #"{"jsonrpc":"2.0","id":12,"method":"prompts/list"}"#))
        let json = try decode(line)
        let matches = json.object?["result"]?.object?["prompts"]?.arrayValue?
            .filter { $0.object?["name"]?.stringValue == "a__b" } ?? []
        #expect(matches.count == 1)   // solo uno, el segundo se descartó
    }
}
