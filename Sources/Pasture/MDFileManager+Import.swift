import Foundation
import PastureKit

extension MDFileManager {

    // MARK: — Import

    /// Imports a file into the library. Convertible documents (PDF, CSV, DOCX/DOC)
    /// go through `DocumentImporter`; anything else is copied as Markdown.
    @discardableResult
    func importFile(from sourceURL: URL, collection: String? = nil) -> MDFile? {
        do {
            guard let markdown = try DocumentImporter.markdownContent(for: sourceURL) else {
                return importMarkdown(from: sourceURL, collection: collection)
            }
            let name = sourceURL.deletingPathExtension().lastPathComponent
            return create(name: name, content: markdown, collection: collection)
        } catch {
            lastError = error.localizedDescription
            return nil
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
        let dest = FileLibrary.deduplicatedURL(baseName: cleanName, ext: ext, in: targetDir)
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
