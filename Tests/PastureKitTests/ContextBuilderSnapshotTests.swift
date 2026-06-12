import Testing
@testable import PastureKit

/// SEC-10 — Snapshot byte-idéntico del formato XML de v1.3.0.
///
/// Estos golden se capturaron ANTES de parametrizar ContextBuilder por formato.
/// Cualquier cambio en la salida XML (default) que rompa estas aserciones es una
/// regresión: el formato XML debe permanecer byte-a-byte idéntico a v1.3.0,
/// incluido el escape de `]]>` y el `xmlEscapedAttribute` del nombre.
@Suite("ContextBuilder XML snapshot (SEC-10)")
struct ContextBuilderSnapshotTests {

    // MARK: — Golden fixtures (v1.3.0, formato XML+CDATA)

    /// Un solo fichero: tag `<context>` sin envoltorio `<documents>`.
    private let singleFileGolden = """
    <context name="notes.md">
    <![CDATA[Hello world]]>
    </context>
    """

    /// Varios ficheros: envueltos en `<documents>`, separados por `\\n`.
    private let multiFileGolden = """
    <documents>
    <context name="a.md">
    <![CDATA[aaa]]>
    </context>
    <context name="b.md">
    <![CDATA[bbb]]>
    </context>
    </documents>
    """

    /// Contenido con `]]>`: escape a `]]]]><![CDATA[>` (defensa anti-inyección CDATA).
    private let cdataInjectionGolden = """
    <context name="tricky.md">
    <![CDATA[before ]]]]><![CDATA[> after]]>
    </context>
    """

    // MARK: — Aserciones byte-idénticas

    @Test("Single-file XML byte-identical to v1.3.0")
    func singleFileSnapshot() {
        let entry = ContextBuilder.FileEntry(name: "notes", content: "Hello world")
        #expect(ContextBuilder.build(files: [entry], format: .xml) == singleFileGolden)
    }

    @Test("Multi-file XML byte-identical to v1.3.0")
    func multiFileSnapshot() {
        let files = [
            ContextBuilder.FileEntry(name: "a", content: "aaa"),
            ContextBuilder.FileEntry(name: "b", content: "bbb"),
        ]
        #expect(ContextBuilder.build(files: files, format: .xml) == multiFileGolden)
    }

    @Test("CDATA-injection content XML byte-identical to v1.3.0")
    func cdataInjectionSnapshot() {
        let entry = ContextBuilder.FileEntry(name: "tricky", content: "before ]]> after")
        #expect(ContextBuilder.build(files: [entry], format: .xml) == cdataInjectionGolden)
    }

    @Test("Default format is .xml (retrocompat: build(files:) == build(files:format:.xml))")
    func defaultFormatIsXML() {
        let files = [
            ContextBuilder.FileEntry(name: "a", content: "aaa"),
            ContextBuilder.FileEntry(name: "b", content: "bbb"),
        ]
        #expect(ContextBuilder.build(files: files) == ContextBuilder.build(files: files, format: .xml))
    }

    @Test("Empty selection returns empty string in XML")
    func emptyXMLSnapshot() {
        #expect(ContextBuilder.build(files: [], format: .xml) == "")
    }
}
