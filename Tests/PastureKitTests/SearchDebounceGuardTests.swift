import Testing
import Foundation
import Combine

/// Guardia de la regresión C1 (audit 360, 2026-09-18).
///
/// `ContentView` propagaba la consulta de búsqueda con
/// `Just(searchText).debounce(for:scheduler:)`. `debounce` de Combine **descarta**
/// el valor pendiente cuando el upstream completa, y `Just` completa de inmediato,
/// así que el sink no se invocaba nunca: teclear en la barra de búsqueda de la
/// ventana principal no filtraba nada, y de rebote `isSearching` era siempre falso
/// (con lo que el invariante "buscar no persiste el plegado" no se ejercía en
/// producción) y `pasture://search?q=` era inerte.
///
/// El bug vivía en la capa SwiftUI, que no es testeable desde aquí. Estas dos
/// guardias cubren lo que sí se puede cubrir: que el patrón no vuelva al árbol, y
/// que la premisa de Combine en la que se apoya el arreglo siga siendo cierta.
@Suite("Búsqueda — guardia del debounce (C1)")
struct SearchDebounceGuardTests {

    /// Raíz del repositorio, deducida de la ubicación de este fichero.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/PastureKitTests/<este fichero>
            .deletingLastPathComponent()      // Tests/PastureKitTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // raíz
    }

    private static func swiftSources(under relativePath: String) throws -> [URL] {
        let root = repoRoot.appendingPathComponent(relativePath)
        let contents = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        return contents
            .filter { $0.hasSuffix(".swift") }
            .map { root.appendingPathComponent($0) }
    }

    @Test("El árbol no vuelve a combinar Just(...) con .debounce")
    func noJustDebounceInAppSources() throws {
        // La guardia se aplica a los dos targets con código de interfaz y de
        // dominio; el ejecutable MCP no usa Combine.
        let sources = try Self.swiftSources(under: "Sources/Pasture")
            + Self.swiftSources(under: "Sources/PastureKit")
        #expect(!sources.isEmpty, "la guardia no encontró fuentes que revisar")

        var ofensores: [String] = []
        for url in sources {
            let texto = try String(contentsOf: url, encoding: .utf8)
            // Se buscan en la misma línea porque así es como se escribe la cadena
            // de operadores, que es la forma en que apareció la regresión. Las
            // líneas de comentario se saltan: el propio arreglo nombra el patrón
            // para explicar por qué está prohibido.
            for (n, linea) in texto.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let codigo = linea.trimmingCharacters(in: .whitespaces)
                guard !codigo.hasPrefix("//") else { continue }
                if codigo.contains("Just(") && codigo.contains(".debounce") {
                    ofensores.append("\(url.lastPathComponent):\(n + 1)")
                }
            }
        }
        #expect(ofensores.isEmpty, """
            `Just(x).debounce(...)` no entrega nunca: el upstream completa de \
            inmediato y el valor pendiente se descarta. Para un debounce en SwiftUI \
            usar `.task(id:)` + `Task.sleep`. Reapariciones: \(ofensores)
            """)
    }

    @Test("Premisa del arreglo: Just(...).debounce no entrega, un subject sí")
    func combineDropsPendingValueOnCompletion() async throws {
        actor Recibidos {
            var valores: [String] = []
            func añadir(_ v: String) { valores.append(v) }
        }
        let deJust = Recibidos()
        let deSubject = Recibidos()
        var bag = Set<AnyCancellable>()
        // Cola propia: no depende de que el run loop principal esté siendo servido.
        let cola = DispatchQueue(label: "pasture.tests.debounce")

        Just("just")
            .debounce(for: .milliseconds(20), scheduler: cola)
            .sink { v in Task { await deJust.añadir(v) } }
            .store(in: &bag)

        let subject = PassthroughSubject<String, Never>()
        subject
            .debounce(for: .milliseconds(20), scheduler: cola)
            .sink { v in Task { await deSubject.añadir(v) } }
            .store(in: &bag)
        subject.send("subject")

        // Margen amplio sobre los 20 ms del debounce para que no dependa de la carga.
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(await deJust.valores.isEmpty,
                "si Combine cambiara y Just(...).debounce entregase, el comentario del arreglo sobraría")
        #expect(await deSubject.valores == ["subject"],
                "el control debe entregar; si no, la prueba no está midiendo nada")
    }
}
