import Foundation

/// Formato del PAYLOAD del feed (contenido generado por ContextBuilder).
///
/// INDEPENDIENTE de `ExportFileFormat` (que solo decide la extensión del fichero
/// al exportar a disco). Son dos settings ortogonales: se puede exportar payload
/// XML a un fichero `.md`, o payload Markdown a un `.txt`. (ADR-005)
public enum FeedFormat: String, Codable, CaseIterable, Sendable {
    /// `<context>…<![CDATA[…]]></context>` — DEFAULT, byte-idéntico a v1.3.0.
    case xml
    /// `## filename` + bloque con fence dinámico (CommonMark).
    case markdown
    /// Cabecera con nombre + contenido, sin etiquetas ni fences.
    case plainText

    public var displayName: String {
        switch self {
        case .xml: return "XML (CDATA)"
        case .markdown: return "Markdown"
        case .plainText: return "Plain text"
        }
    }
}
