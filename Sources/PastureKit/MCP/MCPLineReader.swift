import Foundation

/// Lector de líneas de stdin con límite duro de tamaño (SEC-M3).
///
/// El framing MCP es "una línea = un mensaje" delimitado por `\n`, sin
/// `Content-Length`. Un `readLine()` ingenuo ante una línea de gigabytes sin
/// `\n` acumula todo en memoria → OOM. Este lector descarta cualquier línea que
/// exceda `maxLineBytes` (emitiendo `.oversized`) y se recupera en el siguiente
/// `\n`, sin acumular ilimitadamente.
///
/// Lee con `FileHandle.availableData`, que entrega lo disponible en cuanto llega
/// (sin esperar a reunir N bytes ni a EOF). Es lo que permite que la respuesta al
/// `initialize` salga de inmediato con stdin abierto — el contrato que un cliente
/// MCP interactivo necesita.
///
/// Es Swift puro sobre un `FileHandle`, así que se testea con un `Pipe` sin
/// arrancar un proceso (ADR-004).
public final class MCPLineReader {
    public enum Item: Equatable {
        case line(String)
        case oversized
    }

    private let handle: FileHandle
    private let maxLineBytes: Int

    /// Bytes de la línea en construcción (sin el `\n` final).
    private var buffer = Data()
    /// Cierto mientras se descarta la cola de una línea ya marcada oversized.
    private var discardingUntilNewline = false
    private var reachedEOF = false

    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    public init(handle: FileHandle, maxLineBytes: Int = MCPLimits.maxInputLineBytes) {
        self.handle = handle
        self.maxLineBytes = maxLineBytes
    }

    /// Siguiente línea válida, `.oversized` si una línea superó el cap, o `nil`
    /// al llegar a EOF sin más datos.
    public func next() -> Item? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: Self.newline) {
                // Una línea CON `\n` también puede ser oversized: si la porción
                // hasta el `\n` excede el cap, se descarta (no se entrega).
                let lineLength = buffer.distance(from: buffer.startIndex, to: newlineIndex)
                if !discardingUntilNewline && lineLength > maxLineBytes {
                    buffer.removeSubrange(buffer.startIndex...newlineIndex)
                    return .oversized
                }
                return consumeLine(upTo: newlineIndex)
            }
            // Sin `\n` en el buffer: si ya excede el cap, es oversized (entra en
            // modo descarte hasta el próximo `\n`, sin acumular más memoria).
            if !discardingUntilNewline && buffer.count > maxLineBytes {
                buffer.removeAll(keepingCapacity: true)
                discardingUntilNewline = true
                return .oversized
            }
            if reachedEOF {
                return drainAtEOF()
            }
            readMore()
        }
    }

    /// Extrae la línea hasta (sin incluir) el `\n` y la consume del buffer.
    /// Si estábamos descartando una oversized, esta línea es su cola: se tira.
    private func consumeLine(upTo newlineIndex: Data.Index) -> Item {
        let lineData = Data(buffer[buffer.startIndex..<newlineIndex])
        buffer.removeSubrange(buffer.startIndex...newlineIndex)

        if discardingUntilNewline {
            discardingUntilNewline = false
            // La cola de la oversized ya se señaló; sigue con la siguiente línea.
            return next() ?? .line("")
        }
        return .line(decode(lineData))
    }

    /// En EOF: emite el resto del buffer como última línea (si no se estaba
    /// descartando) y luego termina.
    private func drainAtEOF() -> Item? {
        defer { buffer.removeAll(keepingCapacity: false) }
        if discardingUntilNewline { return nil }
        guard !buffer.isEmpty else { return nil }
        return .line(decode(buffer))
    }

    private func readMore() {
        // `availableData` bloquea hasta ≥1 byte y devuelve lo DISPONIBLE (Data vacía
        // = EOF). Crítico para stdio interactivo: `read(upToCount:)` bloqueaba hasta
        // reunir N bytes o EOF, reteniendo la respuesta al `initialize` hasta el
        // siguiente input — el cliente MCP agotaba el timeout. El cap SEC-M3 se
        // aplica sobre `buffer`, no sobre el tamaño del chunk, así que no cambia.
        let chunk = handle.availableData
        if !chunk.isEmpty {
            // En modo descarte no acumulamos bytes salvo para encontrar el `\n`.
            if discardingUntilNewline {
                if let newlineIndex = chunk.firstIndex(of: Self.newline) {
                    buffer = Data(chunk[newlineIndex...])   // reanuda tras el `\n`
                    discardingUntilNewline = false
                }
                // Si no hay `\n`, se descarta el chunk entero (no crece la RAM).
            } else {
                buffer.append(chunk)
            }
        } else {
            reachedEOF = true
        }
    }

    /// Decodifica una línea a String, quitando un posible `\r` final (CRLF).
    private func decode(_ data: Data) -> String {
        var trimmed = data
        if trimmed.last == Self.carriageReturn {
            trimmed.removeLast()
        }
        return String(decoding: trimmed, as: UTF8.self)
    }
}
