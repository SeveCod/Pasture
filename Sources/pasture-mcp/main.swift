import Foundation
import PastureKit

// stderr para logs; stdout SAGRADO solo para mensajes MCP (gotcha 1-2, SEC-M7).
func log(_ message: String) {
    FileHandle.standardError.write(Data("[pasture-mcp] \(message)\n".utf8))
}

let dispatcher = MCPDispatcher(config: .fromEnvironment())   // ADR-007
let reader = MCPLineReader(handle: .standardInput)           // SEC-M3: cap de línea
log("ready, reading stdin…")

// Loop secuencial síncrono (ADR-005): una línea, una respuesta, sin async.
while let item = reader.next() {
    switch item {
    case .oversized:
        // SEC-M3: línea > 10 MB descartada. No filtramos su contenido al log.
        log("input line exceeded size limit; discarded")
    case .line(let line):
        if line.isEmpty { continue }
        if let response = dispatcher.handle(line: line) {
            FileHandle.standardOutput.write(Data(response.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))   // framing newline (gotcha 7)
        }
    }
}

log("stdin closed, exiting.")   // EOF ⇒ salida limpia (no hay shutdown MCP)
