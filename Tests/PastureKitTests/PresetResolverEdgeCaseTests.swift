import Testing
import Foundation
@testable import PastureKit

/// F2 — Edge cases de PresetResolver detectados en QA v1.4.
/// Documenta el comportamiento real ante entradas degeneradas que los tests
/// principales no cubren: ruta vacía, punto solo, y ruta absoluta como componente.
/// Estos no son bugs de seguridad (SEC-9 se cumple) pero sí comportamiento
/// no documentado que el senior-dev debe evaluar.
@Suite("PresetResolver edge cases (QA v1.4)")
struct PresetResolverEdgeCaseTests {

    private let base = URL(fileURLWithPath: "/Users/test/.pasture", isDirectory: true)

    /// Ruta vacía "" → appendingPathComponent("") devuelve la base misma.
    /// PathValidator lo acepta (base == target). El URL acaba en la lista pero
    /// no matcheará ningún MDFile en la librería (no hay fichero con esa URL).
    /// El resultado es inofensivo (cero ficheros seleccionados), pero no es obvio.
    @Test("Empty string path resolves to base (inofensivo, no selecciona MDFile)")
    func emptyStringPath() {
        let result = PresetResolver.resolve(relativePaths: [""], base: base)
        // No se rechaza (no es path traversal), pero tampoco es un fichero real.
        #expect(result.rejectedCount == 0)
        // El URL resultante es el directorio base, no un fichero útil.
        let resolvedPath = result.urls.first?.standardizedFileURL.path ?? ""
        #expect(resolvedPath == base.standardizedFileURL.path)
    }

    /// Ruta "." → appendingPathComponent(".") se estandariza a la base misma.
    /// Mismo comportamiento que la ruta vacía.
    @Test("Dot path resolves to base (inofensivo, no selecciona MDFile)")
    func dotPath() {
        let result = PresetResolver.resolve(relativePaths: ["."], base: base)
        #expect(result.rejectedCount == 0)
        let resolvedPath = result.urls.first?.standardizedFileURL.path ?? ""
        #expect(resolvedPath == base.standardizedFileURL.path)
    }

    /// Ruta con solo espacios " " → queda dentro de la base (añade componente " ").
    /// No hay fichero con nombre " " en la librería. Inofensivo.
    @Test("Whitespace-only path resolves inside base (inofensivo)")
    func whitespaceOnlyPath() {
        let result = PresetResolver.resolve(relativePaths: [" "], base: base)
        #expect(result.rejectedCount == 0)
        // El URL resultante contiene el espacio como componente, sigue dentro de la base.
        #expect(result.urls.first?.path.hasPrefix(base.path) == true)
    }

    /// Ruta absoluta "/etc/passwd" → appendingPathComponent trata como componente relativo
    /// en este contexto (Swift Foundation), quedando dentro de la base. SEC-9 se mantiene.
    @Test("Absolute-looking path component stays inside base — SEC-9 holds")
    func absoluteLookingPath() {
        let result = PresetResolver.resolve(relativePaths: ["/etc/passwd"], base: base)
        // No rechazado porque appendingPathComponent("/etc/passwd") produce una URL
        // que sigue dentro de la base cuando la base es absoluta.
        // Verificamos que la URL resuelta está DENTRO de la base (invariante de seguridad).
        if let url = result.urls.first {
            #expect(url.path.hasPrefix(base.path))
        }
        // No es un path traversal en el sentido de salir de la base.
        // El fichero "/etc/passwd" como tal no existe como MDFile.
    }
}
