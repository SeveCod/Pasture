import Foundation
import PDFKit

/// Converts importable documents (PDF, CSV, DOCX/DOC) into Markdown content.
/// Pure transformation — no persistence. `MDFileManager+Import` handles writing
/// the result into the library.
public enum DocumentImporter {

    public enum ImportError: Error, LocalizedError, Equatable {
        case unreadable(String)
        case emptyPDF(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name):
                return "Failed to read \(name)"
            case .emptyPDF(let name):
                return "No text extracted from \(name) — scanned PDFs without an OCR layer are not supported"
            }
        }
    }

    /// Returns the Markdown content for a convertible document, or `nil` when the
    /// file is not a conversion type (e.g. `.md` — caller should copy it as-is).
    public static func markdownContent(for url: URL) throws -> String? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try pdfText(from: url)
        case "csv":
            return CSVConverter.convert(try csvText(from: url))
        case "docx", "doc":
            return try DOCXConverter.convert(url: url)
        default:
            return nil
        }
    }

    /// Extracts plain text from a PDF. Throws `emptyPDF` when no text could be
    /// extracted (scanned documents without OCR) instead of producing an empty file.
    static func pdfText(from url: URL) throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        let text = pages.joined(separator: "\n\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyPDF(url.lastPathComponent)
        }
        return text
    }

    /// Reads CSV text as UTF-8, falling back to Latin-1 for legacy exports.
    static func csvText(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            return latin1
        }
        throw ImportError.unreadable(url.lastPathComponent)
    }
}
