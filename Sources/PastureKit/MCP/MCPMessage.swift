import Foundation

// MARK: — JSON-RPC 2.0 id (string | number | ausente)

/// id de JSON-RPC 2.0: puede ser string, number o estar ausente (notificación).
/// Se ecoa idéntico en la respuesta. `Sendable` para Swift 6.
public enum JSONRPCID: Codable, Equatable, Sendable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container, debugDescription: "id no es string ni number")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        }
    }
}

// MARK: — JSONValue (params/arguments sin [String: Any])

/// Valor JSON genérico `Codable`/`Sendable`. Sustituye a `[String: Any]`, que no
/// es `Sendable` ni `Codable` en Swift 6 strict. Cada tool extrae sus campos
/// tipados (`value.object?["path"]?.stringValue`) sin castear `Any`.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "valor JSON no soportado")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // Accessors tipados — devuelven nil si el tipo no coincide.

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Alias legible usado por las tools.
    public var arrayValue: [JSONValue]? { array }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

// MARK: — Mensajes JSON-RPC

/// Request o notificación entrante. `params` se decodifica bajo demanda por cada
/// tool.
///
/// Spec JSON-RPC 2.0: una **notificación** es un Request SIN el miembro `id`. Un
/// `id:null` EXPLÍCITO es un Request (inválido, pero request): hay que responderlo,
/// no silenciarlo. Por eso `init(from:)` distingue los tres estados con
/// `idPresence`, que `Optional<JSONRPCID>` por sí solo colapsaría (ambos a `nil`).
public struct JSONRPCRequest: Decodable, Sendable {
    /// Estado del miembro `id` en el JSON entrante.
    public enum IDPresence: Sendable, Equatable {
        case absent              // sin miembro `id` ⇒ notificación
        case explicitNull        // `id:null` presente ⇒ request inválido
        case value(JSONRPCID)    // `id` con string/number
    }

    public let jsonrpc: String
    public let idPresence: IDPresence
    public let method: String
    public let params: JSONValue?

    /// `id` utilizable para ecoar en la respuesta. `nil` si ausente o null.
    public var id: JSONRPCID? {
        if case .value(let id) = idPresence { return id }
        return nil
    }

    /// Solo es notificación si el miembro `id` está AUSENTE (gotcha 5).
    public var isNotification: Bool { idPresence == .absent }

    /// `id:null` explícito: request técnicamente inválido (spec lo desaconseja).
    public var hasExplicitNullID: Bool { idPresence == .explicitNull }

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        self.method = try container.decode(String.self, forKey: .method)
        self.params = try container.decodeIfPresent(JSONValue.self, forKey: .params)

        if !container.contains(.id) {
            self.idPresence = .absent
        } else if try container.decodeNil(forKey: .id) {
            self.idPresence = .explicitNull
        } else {
            self.idPresence = .value(try container.decode(JSONRPCID.self, forKey: .id))
        }
    }
}

/// Respuesta de éxito. `result` es genérico por método (`Encodable`).
public struct JSONRPCResponse<R: Encodable>: Encodable {
    public let jsonrpc = "2.0"
    public let id: JSONRPCID
    public let result: R

    public init(id: JSONRPCID, result: R) {
        self.id = id
        self.result = result
    }

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, result }
}

/// Respuesta de ERROR DE PROTOCOLO (objeto `error` JSON-RPC). NO es el `isError`
/// de una tool: este tumbaría una request mal formada, no un fallo de tool.
public struct JSONRPCErrorResponse: Encodable {
    public struct ErrorBody: Encodable {
        public let code: Int
        public let message: String

        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }
    }

    public let jsonrpc = "2.0"
    public let id: JSONRPCID?
    public let error: ErrorBody

    public init(id: JSONRPCID?, error: ErrorBody) {
        self.id = id
        self.error = error
    }

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, error }

    /// La spec JSON-RPC exige que el `id` de un error sea `null` EXPLÍCITO cuando
    /// no hay id correlacionable (parse error), no una clave ausente. `Encodable`
    /// por defecto omitiría la clave para un Optional nil, así que se fuerza.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(error, forKey: .error)
        if let id {
            try container.encode(id, forKey: .id)
        } else {
            try container.encodeNil(forKey: .id)
        }
    }
}

// MARK: — Serialización limpia (gotcha 7, ADR-006)

public extension Encodable {
    /// Serializa a UNA línea: sin newlines de pretty-print, claves ordenadas
    /// (golden tests deterministas) y SIN escapar `/`. Los `\n` embebidos del
    /// contenido se escapan dentro del string → framing newline a salvo.
    func mcpLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}
