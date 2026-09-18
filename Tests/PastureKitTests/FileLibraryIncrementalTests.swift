import Testing
import Foundation
@testable import PastureKit

/// Carga incremental (audit 360, A3). El riesgo de una caché no es la lentitud
/// sino la CORRECCIÓN: una nota obsoleta servida desde caché viajaría a un feed,
/// a una respuesta de Ask o al `CLAUDE.md` de un repo vía PackWriter. Por eso la
/// afirmación "un fichero cambiado siempre se relee" se prueba barriendo la
/// rejilla de formas de cambiarlo, no con un vector elegido.
@Suite("FileLibrary — carga incremental")
struct FileLibraryIncrementalTests {

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    /// Fuerza una fecha de modificación distinta y conocida.
    private func touch(_ url: URL, secondsAgo: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: url.path)
    }

    @Test("Sin cambios, la nota se reutiliza (no se vuelve a leer del disco)")
    func reusesUnchangedEntry() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nota = dir.appendingPathComponent("a.md")

        // El señuelo en disco tiene EXACTAMENTE los mismos bytes que el contenido
        // que se declara cacheado, así que si la carga releyese el fichero el
        // contenido cambiaría y se notaría.
        let enDisco = "contenido MODIFICA"
        let cacheado = "contenido original"
        #expect(enDisco.utf8.count == cacheado.utf8.count)
        try write(enDisco, to: nota)

        // La entrada de caché se construye a mano con la fecha REAL del fichero.
        // (Forzarla con `setAttributes` no sirve: ese round-trip pierde precisión
        // sub-nanosegundo y la fecha deja de ser idéntica — medido.)
        let fechaReal = try #require(
            try nota.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let entradaCache = MDFile(
            name: "a", url: nota, modifiedDate: fechaReal,
            content: cacheado, tokens: 0, hasTemplateVars: false)

        let result = await FileLibrary.load(at: dir, reusing: [entradaCache])
        #expect(result.files.first?.content == cacheado,
                "con fecha y tamaño idénticos la entrada debe reutilizarse, no releerse")
    }

    @Test("Cualquier cambio real fuerza la relectura",
          arguments: [
            "mas-largo",
            "corto",
            "misma-longitud",
          ])
    func rereadsOnRealChange(caso: String) async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nota = dir.appendingPathComponent("a.md")
        let original = "contenido original"
        try write(original, to: nota)
        try touch(nota, secondsAgo: 60)

        let primera = await FileLibrary.load(at: dir)
        #expect(primera.files.first?.content == original)

        let nuevo: String = switch caso {
        case "mas-largo":      original + " con mucha más cola detrás"
        case "corto":          "x"
        default:               String(original.reversed())   // misma longitud exacta
        }
        try write(nuevo, to: nota)
        // El caso "misma-longitud" sólo lo distingue la fecha; los otros dos,
        // también el tamaño. Se deja que el sistema fije la fecha actual.

        let segunda = await FileLibrary.load(at: dir, reusing: primera.files)
        #expect(segunda.files.first?.content == nuevo,
                "\(caso): un fichero modificado debe releerse, no servirse de caché")
    }

    @Test("Las notas derivadas se recalculan al releer, no se arrastran")
    func derivedPropertiesFollowContent() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let nota = dir.appendingPathComponent("a.md")
        try write("texto llano sin plantilla", to: nota)
        try touch(nota, secondsAgo: 60)

        let primera = await FileLibrary.load(at: dir)
        #expect(primera.files.first?.hasTemplateVars == false)

        try write("hola {{NOMBRE}}, van {{N}} cajas", to: nota)
        let segunda = await FileLibrary.load(at: dir, reusing: primera.files)
        #expect(segunda.files.first?.hasTemplateVars == true,
                "tokens/plantillas/frontmatter se derivan del contenido: si la caché los arrastra, la UI miente")
    }

    @Test("Una nota nueva y una borrada se reflejan aunque haya caché")
    func addedAndRemovedFilesAreTracked() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("uno", to: dir.appendingPathComponent("a.md"))
        let primera = await FileLibrary.load(at: dir)
        #expect(primera.files.count == 1)

        try write("dos", to: dir.appendingPathComponent("b.md"))
        let segunda = await FileLibrary.load(at: dir, reusing: primera.files)
        #expect(Set(segunda.files.map(\.name)) == ["a", "b"])

        try FileManager.default.removeItem(at: dir.appendingPathComponent("a.md"))
        let tercera = await FileLibrary.load(at: dir, reusing: segunda.files)
        #expect(tercera.files.map(\.name) == ["b"],
                "una caché no puede resucitar un fichero borrado")
    }
}
