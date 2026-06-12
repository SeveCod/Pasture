import Foundation

public enum ContextBuilder {

    public struct FileEntry: Sendable {
        public let name: String
        public let content: String

        public init(name: String, content: String) {
            self.name = name
            self.content = content
        }
    }

    /// Genera el payload del feed según el formato indicado.
    ///
    /// El default `.xml` garantiza retrocompatibilidad: las llamadas existentes
    /// `build(files:)` siguen produciendo la salida byte-idéntica a v1.3.0 (SEC-10).
    public static func build(files: [FileEntry], format: FeedFormat = .xml) -> String {
        guard !files.isEmpty else { return "" }
        switch format {
        case .xml: return buildXML(files)
        case .markdown: return buildMarkdown(files)
        case .plainText: return buildPlainText(files)
        }
    }

    // MARK: — XML (v1.3.0, intacto)

    /// Salida XML+CDATA byte-idéntica a v1.3.0. NO tocar: el snapshot test (SEC-10)
    /// la blinda contra regresiones.
    static func buildXML(_ files: [FileEntry]) -> String {
        if files.count == 1, let f = files.first {
            return contextTag(name: f.name, content: f.content)
        }
        let inner = files.map { contextTag(name: $0.name, content: $0.content) }.joined(separator: "\n")
        return "<documents>\n\(inner)\n</documents>"
    }

    static func contextTag(name: String, content: String) -> String {
        let body = content.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
        let safeName = "\(name).md".xmlEscapedAttribute
        return "<context name=\"\(safeName)\">\n<![CDATA[\(body)]]>\n</context>"
    }

    // MARK: — Markdown (SEC-11)

    /// `## name.md` + bloque con fence dinámico (CommonMark). El fence envolvente
    /// es estrictamente más largo que la secuencia de backticks más larga del
    /// contenido, de modo que el contenido nunca rompe el bloque envolvente.
    /// El nombre se neutraliza (sin saltos de línea) para no inyectar cabeceras.
    static func buildMarkdown(_ files: [FileEntry]) -> String {
        files.map { markdownBlock(name: $0.name, content: $0.content) }
            .joined(separator: "\n\n")
    }

    private static func markdownBlock(name: String, content: String) -> String {
        let safeName = neutralizedName(name)
        let fence = String(repeating: "`", count: max(3, longestBacktickRun(in: content) + 1))
        return "## \(safeName).md\n\(fence)\n\(content)\n\(fence)"
    }

    /// Longitud de la secuencia más larga de backticks consecutivos en el texto.
    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                if current > longest { longest = current }
            } else {
                current = 0
            }
        }
        return longest
    }

    // MARK: — Plain text (SEC-12)

    /// Cabecera con el nombre del fichero como marca contextual + contenido.
    /// Formato LOSSY/best-effort: pensado para pegar en un chat, no para
    /// des-serializar sin ambigüedad. El separador incluye el nombre para que,
    /// aunque el contenido imite la línea separadora, exista una marca contextual.
    /// El nombre se neutraliza (sin saltos de línea).
    static func buildPlainText(_ files: [FileEntry]) -> String {
        files.map { plainTextBlock(name: $0.name, content: $0.content) }
            .joined(separator: "\n\n")
    }

    private static func plainTextBlock(name: String, content: String) -> String {
        let safeName = neutralizedName(name)
        return "===== \(safeName).md =====\n\(content)"
    }

    // MARK: — Helpers

    /// Sustituye saltos de línea por espacios para que un nombre de fichero no
    /// pueda inyectar estructura en formatos sin envoltura (Markdown/plano).
    private static func neutralizedName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
