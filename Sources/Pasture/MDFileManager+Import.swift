import Foundation
import PDFKit
import PastureKit

extension MDFileManager {

    // MARK: — Import

    @discardableResult
    func importFile(from sourceURL: URL, collection: String? = nil) -> MDFile? {
        switch sourceURL.pathExtension.lowercased() {
        case "pdf":
            return importPDF(from: sourceURL, collection: collection)
        case "csv":
            return importCSV(from: sourceURL, collection: collection)
        case "docx", "doc":
            return importDOCX(from: sourceURL, collection: collection)
        default:
            return importMarkdown(from: sourceURL, collection: collection)
        }
    }

    @discardableResult
    private func importMarkdown(from sourceURL: URL, collection: String? = nil) -> MDFile? {
        guard let targetDir = resolveTargetDirectory(collection: collection) else {
            lastError = "Invalid collection path"
            return nil
        }

        let cleanName = FilenameSanitizer.sanitize(sourceURL.deletingPathExtension().lastPathComponent)
        guard !cleanName.isEmpty else {
            lastError = "Invalid file name"
            return nil
        }
        let ext = sourceURL.pathExtension
        let dest = Self.deduplicatedURL(baseName: cleanName, ext: ext, in: targetDir)
        guard Self.isInsidePasture(dest) else { return nil }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            let newFile = MDFile(url: dest)
            files.insert(newFile, at: 0)
            return newFile
        } catch {
            lastError = "Failed to import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    func importPDF(from sourceURL: URL, collection: String? = nil) -> MDFile? {
        guard let doc = PDFDocument(url: sourceURL) else {
            lastError = "Failed to open PDF: \(sourceURL.lastPathComponent)"
            return nil
        }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        let text = pages.joined(separator: "\n\n")
        let name = sourceURL.deletingPathExtension().lastPathComponent
        return create(name: name, content: text, collection: collection)
    }

    @discardableResult
    func importCSV(from sourceURL: URL, collection: String? = nil) -> MDFile? {
        let csvText: String
        if let utf8 = try? String(contentsOf: sourceURL, encoding: .utf8) {
            csvText = utf8
        } else if let latin1 = try? String(contentsOf: sourceURL, encoding: .isoLatin1) {
            csvText = latin1
        } else {
            lastError = "Failed to read CSV: \(sourceURL.lastPathComponent)"
            return nil
        }
        let markdown = CSVConverter.convert(csvText)
        let name = sourceURL.deletingPathExtension().lastPathComponent
        return create(name: name, content: markdown, collection: collection)
    }

    @discardableResult
    func importDOCX(from sourceURL: URL, collection: String? = nil) -> MDFile? {
        do {
            let markdown = try DOCXConverter.convert(url: sourceURL)
            let name = sourceURL.deletingPathExtension().lastPathComponent
            return create(name: name, content: markdown, collection: collection)
        } catch {
            lastError = "Failed to import DOCX: \(error.localizedDescription)"
            return nil
        }
    }

    func merge(files toMerge: [MDFile], into name: String) -> MDFile? {
        let combined = toMerge.map(\.content).joined(separator: "\n---\n")
        return create(name: name, content: combined)
    }

    // MARK: — Scan Folder

    @discardableResult
    func scanFolder(at folderURL: URL) -> Int {
        let folderName = FilenameSanitizer.sanitize(folderURL.lastPathComponent)
        guard !folderName.isEmpty else {
            lastError = "Invalid folder name"
            return 0
        }

        _ = createCollection(name: folderName)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            lastError = "Cannot read folder"
            return 0
        }

        var count = 0
        let maxFiles = 500
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            importFile(from: fileURL, collection: folderName)
            count += 1
            if count >= maxFiles { break }
        }

        if count == 0 {
            lastError = "No .md files found in \(folderName)"
        }
        return count
    }
}
