import Testing
import Foundation
@testable import PastureKit

/// Bloque 1 del diseño: tipos JSON-RPC + serialización (`mcpLine()`).
/// Aquí se blinda el gotcha 7 (framing newline + `.withoutEscapingSlashes`).
@Suite struct MCPProtocolTests {

    // MARK: — JSONRPCID: string | number (Codable manual)

    @Test func idDecodesNumber() throws {
        let data = Data("42".utf8)
        let id = try JSONDecoder().decode(JSONRPCID.self, from: data)
        #expect(id == .number(42))
    }

    @Test func idDecodesString() throws {
        let data = Data("\"abc\"".utf8)
        let id = try JSONDecoder().decode(JSONRPCID.self, from: data)
        #expect(id == .string("abc"))
    }

    @Test func idNumberRoundTrips() throws {
        let original = JSONRPCID.number(7)
        let data = try JSONEncoder().encode(original)
        #expect(String(decoding: data, as: UTF8.self) == "7")
    }

    @Test func idStringRoundTrips() throws {
        let original = JSONRPCID.string("req-1")
        let data = try JSONEncoder().encode(original)
        #expect(String(decoding: data, as: UTF8.self) == "\"req-1\"")
    }

    // MARK: — Notificación detectada por ausencia de id (gotcha 5)

    @Test func requestWithoutIdIsNotification() throws {
        let json = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        let req = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(req.isNotification)
        #expect(req.id == nil)
    }

    @Test func requestWithIdIsNotNotification() throws {
        let json = #"{"jsonrpc":"2.0","id":3,"method":"ping"}"#
        let req = try JSONDecoder().decode(JSONRPCRequest.self, from: Data(json.utf8))
        #expect(!req.isNotification)
        #expect(req.id == .number(3))
    }

    // MARK: — JSONValue: extracción tipada sin [String: Any]

    @Test func jsonValueExtractsNestedStringArgument() throws {
        let json = #"{"path":"notes/a.md"}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(value.object?["path"]?.stringValue == "notes/a.md")
    }

    @Test func jsonValueExtractsStringArray() throws {
        let json = #"{"files":["a.md","b.md"]}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let files = value.object?["files"]?.arrayValue?.compactMap { $0.stringValue }
        #expect(files == ["a.md", "b.md"])
    }

    // MARK: — mcpLine(): gotcha 7 (framing + slashes + claves ordenadas)

    /// El contenido con `\n` embebidos NO debe contener un newline literal tras
    /// serializar: una línea = un mensaje, framing newline-delimited a salvo.
    @Test func mcpLineEscapesEmbeddedNewlines() throws {
        struct Payload: Encodable { let text: String }
        let line = try Payload(text: "linea1\nlinea2\nlinea3").mcpLine()
        #expect(!line.contains("\n"))
        #expect(line.contains(#"\n"#))
    }

    /// `.withoutEscapingSlashes`: no debe aparecer `\/` (corrección al spike).
    @Test func mcpLineDoesNotEscapeSlashes() throws {
        struct Payload: Encodable { let path: String }
        let line = try Payload(path: "notes/sub/a.md").mcpLine()
        #expect(line.contains("notes/sub/a.md"))
        #expect(!line.contains(#"\/"#))
    }

    /// `.sortedKeys`: orden determinista para golden tests.
    @Test func mcpLineSortsKeys() throws {
        struct Payload: Encodable { let zebra: Int; let alpha: Int }
        let line = try Payload(zebra: 1, alpha: 2).mcpLine()
        let alphaPos = line.range(of: "alpha")!.lowerBound
        let zebraPos = line.range(of: "zebra")!.lowerBound
        #expect(alphaPos < zebraPos)
    }
}
