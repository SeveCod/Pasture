import Testing
@testable import PastureKit
import Foundation
import PDFKit

@Suite struct DocumentImporterTests {

    // MARK: - Dispatch

    @Test func markdownAndUnknownExtensionsReturnNil() throws {
        // nil → caller copies the file as-is (no conversion)
        let md = URL(fileURLWithPath: "/tmp/notes.md")
        let txt = URL(fileURLWithPath: "/tmp/notes.txt")
        #expect(try DocumentImporter.markdownContent(for: md) == nil)
        #expect(try DocumentImporter.markdownContent(for: txt) == nil)
    }

    @Test func csvIsConvertedToMarkdownTable() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("data.csv")
        try "name,age\nAna,30".write(to: url, atomically: true, encoding: .utf8)

        let markdown = try #require(try DocumentImporter.markdownContent(for: url))
        #expect(markdown.contains("| name | age |"))
        #expect(markdown.contains("| Ana | 30 |"))
    }

    // MARK: - CSV encoding fallback

    @Test func csvTextFallsBackToLatin1() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("legacy.csv")
        // "café" in Latin-1: 0xE9 is not valid UTF-8, forcing the fallback path
        let latin1Data = "café".data(using: .isoLatin1)!
        try latin1Data.write(to: url)

        let text = try DocumentImporter.csvText(from: url)
        #expect(text == "café")
    }

    @Test func csvTextThrowsForMissingFile() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).csv")
        #expect(throws: DocumentImporter.ImportError.unreadable(missing.lastPathComponent)) {
            try DocumentImporter.csvText(from: missing)
        }
    }

    // MARK: - PDF

    @Test func pdfTextThrowsForUnreadableFile() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).pdf")
        #expect(throws: DocumentImporter.ImportError.unreadable(missing.lastPathComponent)) {
            try DocumentImporter.pdfText(from: missing)
        }
    }

    @Test func pdfWithoutTextThrowsEmptyPDF() throws {
        // Regression: a scanned PDF without an OCR layer must raise an error
        // instead of silently creating an empty .md file.
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("scanned.pdf")
        let emptyDoc = PDFDocument()
        #expect(emptyDoc.write(to: url))

        #expect(throws: DocumentImporter.ImportError.emptyPDF("scanned.pdf")) {
            try DocumentImporter.pdfText(from: url)
        }
    }
}
