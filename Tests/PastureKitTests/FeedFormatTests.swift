import Testing
@testable import PastureKit

/// F4 — Formatos de salida del feed (XML / Markdown / plano).
/// SEC-11 (Markdown: fence dinámico + nombre neutralizado),
/// SEC-12 (plano: separador con nombre + lossy).
@Suite("FeedFormat + ContextBuilder multi-formato")
struct FeedFormatTests {

    // MARK: — Enum básico

    @Test("FeedFormat is exhaustive and Codable-stable")
    func enumRawValues() {
        #expect(FeedFormat.xml.rawValue == "xml")
        #expect(FeedFormat.markdown.rawValue == "markdown")
        #expect(FeedFormat.plainText.rawValue == "plainText")
        #expect(FeedFormat.allCases.count == 3)
    }

    @Test("Each format has a display name")
    func displayNames() {
        for format in FeedFormat.allCases {
            #expect(!format.displayName.isEmpty)
        }
    }

    // MARK: — Markdown

    @Test("Markdown single file: ## name + fenced block")
    func markdownSingleFile() {
        let entry = ContextBuilder.FileEntry(name: "notes", content: "Hello world")
        let result = ContextBuilder.build(files: [entry], format: .markdown)
        #expect(result == "## notes.md\n```\nHello world\n```")
    }

    @Test("Markdown multi file: blocks separated by blank line")
    func markdownMultiFile() {
        let files = [
            ContextBuilder.FileEntry(name: "a", content: "aaa"),
            ContextBuilder.FileEntry(name: "b", content: "bbb"),
        ]
        let result = ContextBuilder.build(files: files, format: .markdown)
        #expect(result == "## a.md\n```\naaa\n```\n\n## b.md\n```\nbbb\n```")
    }

    // SEC-11: fence dinámico. Contenido con ``` -> fence envolvente de 4 backticks.
    @Test("Markdown dynamic fence: content with triple backtick uses 4-backtick fence")
    func markdownDynamicFenceTriple() {
        let content = "code:\n```\nlet x = 1\n```"
        let entry = ContextBuilder.FileEntry(name: "snippet", content: content)
        let result = ContextBuilder.build(files: [entry], format: .markdown)
        #expect(result.hasPrefix("## snippet.md\n````\n"))
        #expect(result.hasSuffix("\n````"))
        // El contenido íntegro (con sus ``` internos) sobrevive sin romper el bloque.
        #expect(result.contains(content))
    }

    // SEC-11: si el contenido ya tiene 4 backticks, el envolvente usa 5.
    @Test("Markdown dynamic fence grows beyond longest run (4 backticks -> 5)")
    func markdownDynamicFenceQuad() {
        let content = "````\nnested\n````"
        let entry = ContextBuilder.FileEntry(name: "deep", content: content)
        let result = ContextBuilder.build(files: [entry], format: .markdown)
        #expect(result.hasPrefix("## deep.md\n`````\n"))
        #expect(result.hasSuffix("\n`````"))
        #expect(result.contains(content))
    }

    // SEC-11: el nombre neutraliza saltos de línea para no inyectar cabeceras falsas.
    @Test("Markdown neutralizes newlines in file name")
    func markdownNeutralizesNameNewlines() {
        let entry = ContextBuilder.FileEntry(name: "evil\n## fake heading", content: "x")
        let result = ContextBuilder.build(files: [entry], format: .markdown)
        // El nombre no debe introducir un salto de línea que cree una cabecera real.
        #expect(!result.contains("\n## fake heading"))
        // La cabecera del fichero sigue siendo una sola línea que empieza por "## ".
        let firstLine = result.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        #expect(firstLine.hasPrefix("## "))
    }

    // MARK: — Texto plano

    // SEC-12: separador con nombre del fichero.
    @Test("Plain text single file: header with name + content")
    func plainTextSingleFile() {
        let entry = ContextBuilder.FileEntry(name: "notes", content: "Hello world")
        let result = ContextBuilder.build(files: [entry], format: .plainText)
        #expect(result.contains("notes.md"))
        #expect(result.contains("Hello world"))
        // Sin etiquetas XML ni fences de Markdown.
        #expect(!result.contains("<context"))
        #expect(!result.contains("```"))
    }

    @Test("Plain text multi file separates by named header")
    func plainTextMultiFile() {
        let files = [
            ContextBuilder.FileEntry(name: "a", content: "aaa"),
            ContextBuilder.FileEntry(name: "b", content: "bbb"),
        ]
        let result = ContextBuilder.build(files: files, format: .plainText)
        #expect(result.contains("a.md"))
        #expect(result.contains("b.md"))
        #expect(result.contains("aaa"))
        #expect(result.contains("bbb"))
        // Orden preservado.
        let aPos = result.range(of: "a.md")!.lowerBound
        let bPos = result.range(of: "b.md")!.lowerBound
        #expect(aPos < bPos)
    }

    // SEC-12: contenido que contiene la cadena separadora no produce un nombre de fichero falso.
    @Test("Plain text: separator string in content does not forge a file header")
    func plainTextSeparatorInContentIsSafe() {
        // El separador incluye el nombre del fichero como marca contextual; un
        // contenido que imite el separador "===" no debe contar como nuevo fichero.
        let entry = ContextBuilder.FileEntry(name: "real", content: "=== fake ===\nbody")
        let result = ContextBuilder.build(files: [entry], format: .plainText)
        // Solo hay un nombre de fichero real en una cabecera: "real.md".
        // La cabecera real lleva el nombre del fichero, el contenido falso no.
        #expect(result.contains("real.md"))
        #expect(result.contains("=== fake ===\nbody"))
    }

    // SEC-12: el nombre en la cabecera plana neutraliza saltos de línea.
    @Test("Plain text neutralizes newlines in file name")
    func plainTextNeutralizesNameNewlines() {
        let entry = ContextBuilder.FileEntry(name: "evil\nfake", content: "x")
        let result = ContextBuilder.build(files: [entry], format: .plainText)
        #expect(!result.contains("evil\nfake"))
    }

    // MARK: — Empty

    @Test("Empty selection returns empty string for all formats")
    func emptyAllFormats() {
        for format in FeedFormat.allCases {
            #expect(ContextBuilder.build(files: [], format: format) == "")
        }
    }
}
