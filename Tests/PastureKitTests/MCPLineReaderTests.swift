import Testing
import Foundation
@testable import PastureKit

/// SEC-M3: lector de líneas de stdin con límite duro de tamaño. Una línea que
/// supera el cap sin `\n` no se acumula ilimitadamente — se descarta y se señala.
@Suite struct MCPLineReaderTests {

    /// Crea un FileHandle de lectura a partir de un Data, vía un pipe.
    private func handle(for data: Data) -> FileHandle {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(data)
        try? pipe.fileHandleForWriting.close()
        return pipe.fileHandleForReading
    }

    @Test func readsLinesSplitByNewline() {
        let reader = MCPLineReader(handle: handle(for: Data("line1\nline2\nline3\n".utf8)),
                                   maxLineBytes: 1000)
        var lines: [String] = []
        while let result = reader.next() {
            if case .line(let value) = result { lines.append(value) }
        }
        #expect(lines == ["line1", "line2", "line3"])
    }

    @Test func handlesLastLineWithoutTrailingNewline() {
        let reader = MCPLineReader(handle: handle(for: Data("only\nlast".utf8)),
                                   maxLineBytes: 1000)
        var lines: [String] = []
        while let result = reader.next() {
            if case .line(let value) = result { lines.append(value) }
        }
        #expect(lines == ["only", "last"])
    }

    /// SEC-M3: una línea que excede el cap → .oversized, NO acumulación ilimitada.
    @Test func oversizedLineIsRejectedNotAccumulated() {
        // 50 bytes sin newline, cap de 10 → debe reportar oversized.
        let big = Data(String(repeating: "x", count: 50).utf8)
        let reader = MCPLineReader(handle: handle(for: big), maxLineBytes: 10)
        var sawOversized = false
        while let result = reader.next() {
            if case .oversized = result { sawOversized = true }
        }
        #expect(sawOversized)
    }

    /// Tras una línea sobredimensionada, el reader sigue procesando las siguientes.
    @Test func recoversAfterOversizedLine() {
        // Una línea enorme, luego una válida.
        let data = Data((String(repeating: "x", count: 50) + "\nvalid\n").utf8)
        let reader = MCPLineReader(handle: handle(for: data), maxLineBytes: 10)
        var validLines: [String] = []
        var sawOversized = false
        while let result = reader.next() {
            switch result {
            case .line(let value): validLines.append(value)
            case .oversized: sawOversized = true
            }
        }
        #expect(sawOversized)
        #expect(validLines.contains("valid"))
    }

    @Test func defaultCapIsTenMegabytes() {
        #expect(MCPLimits.maxInputLineBytes == 10_000_000)
    }

    /// REGRESIÓN (bloqueo de entrega v1.5): el reader debe entregar una línea
    /// completa EN CUANTO llega, sin esperar a que se cierre el extremo de
    /// escritura (EOF). El bug original (`read(upToCount:)` bloquea hasta reunir
    /// N bytes o EOF) hacía que la respuesta al `initialize` no se entregara hasta
    /// el siguiente input — el cliente MCP agotaba el timeout.
    ///
    /// Mantenemos el write end ABIERTO a propósito. Si `next()` bloquea, el
    /// semáforo agota su espera corta y el test falla de forma controlada (no
    /// cuelga la suite). Es el escenario que los Pipe que cierran el write end
    /// nunca reprodujeron.
    @Test func deliversLineWithoutWaitingForEOF() {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("first-line\n".utf8))
        // NO cerramos fileHandleForWriting: stdin sigue abierto, como en un cliente real.

        let reader = MCPLineReader(handle: pipe.fileHandleForReading, maxLineBytes: 1000)

        let done = DispatchSemaphore(value: 0)
        let received = LockedBox<MCPLineReader.Item?>(nil)
        Thread.detachNewThread {
            received.value = reader.next()
            done.signal()
        }

        let outcome = done.wait(timeout: .now() + 2)
        // Cerramos el write end para que el hilo no quede colgado si bloqueó.
        try? pipe.fileHandleForWriting.close()

        #expect(outcome == .success, "next() bloqueó esperando EOF en vez de entregar la línea disponible")
        #expect(received.value == .line("first-line"))
    }
}

/// Caja con cerrojo para pasar un valor entre el hilo lector y el test sin
/// data race (Swift 6 strict). Mínima a propósito: solo lo que el test necesita.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T
    init(_ initial: T) { storage = initial }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
