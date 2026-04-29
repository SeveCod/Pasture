import Foundation
import Combine
import PDFKit
import PastureKit

private let pastureDirURL: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".pasture")
}()

private let pastureDirectoryChangedNotification = Notification.Name("PastureDirectoryChanged")

private func makeDirectoryWatchSource(fd: Int32) -> any DispatchSourceFileSystemObject {
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: .write,
        queue: .global(qos: .utility)
    )
    source.setEventHandler {
        NotificationCenter.default.post(name: pastureDirectoryChangedNotification, object: nil)
    }
    source.setCancelHandler {
        close(fd)
    }
    source.resume()
    return source
}

struct MDFile: Identifiable, Hashable {
    var id: URL { url }
    var name: String
    var url: URL
    var modifiedDate: Date
    var content: String
    var tokens: Int
    var hasTemplateVars: Bool

    init(url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.modifiedDate = attrs?[.modificationDate] as? Date ?? Date()
        self.content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        self.tokens = TokenEstimator.estimate(self.content)
        self.hasTemplateVars = TemplateEngine.hasVariables(in: self.content)
    }

    var collection: String? {
        let parentDir = url.deletingLastPathComponent()
        let pastureStandardized = pastureDirURL.standardizedFileURL
        let parentStandardized = parentDir.standardizedFileURL
        guard parentStandardized != pastureStandardized else { return nil }
        guard parentStandardized.path.hasPrefix(pastureStandardized.path) else { return nil }
        return parentDir.lastPathComponent
    }

    mutating func updateDerivedProperties() {
        tokens = TokenEstimator.estimate(content)
        hasTemplateVars = TemplateEngine.hasVariables(in: content)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: MDFile, rhs: MDFile) -> Bool {
        lhs.url == rhs.url
    }
}

@MainActor
final class MDFileManager: ObservableObject {
    @Published var files: [MDFile] = []
    @Published var collections: [String] = []
    @Published var searchQuery: String = ""
    @Published var lastError: String?

    nonisolated(unsafe) private var directorySource: (any DispatchSourceFileSystemObject)?
    nonisolated(unsafe) private var reloadWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var subdirectorySources: [String: any DispatchSourceFileSystemObject] = [:]
    nonisolated(unsafe) private var subdirectoryFDs: [String: Int32] = [:]

    static let pastureDir: URL = pastureDirURL

    var filteredFiles: [MDFile] {
        guard !searchQuery.isEmpty else { return files }
        let q = searchQuery
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    nonisolated(unsafe) private var reloadObserver: (any NSObjectProtocol)?

    // MARK: — Helpers

    private static func isInsidePasture(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.path
        let base = pastureDir.standardizedFileURL.path
        return target == base || target.hasPrefix(base + "/")
    }

    private func resolveTargetDirectory(collection: String?) -> URL? {
        guard let collection else { return Self.pastureDir }
        let collectionDir = Self.pastureDir.appendingPathComponent(collection)
        guard Self.isInsidePasture(collectionDir) else { return nil }
        try? FileManager.default.createDirectory(at: collectionDir, withIntermediateDirectories: true)
        return collectionDir
    }

    private static func deduplicatedURL(baseName: String, ext: String, in directory: URL) -> URL {
        let filename = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        var url = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let numbered = ext.isEmpty ? "\(baseName)-\(counter)" : "\(baseName)-\(counter).\(ext)"
            url = directory.appendingPathComponent(numbered)
            counter += 1
        }
        return url
    }

    private func refreshCollections() {
        collections = Self.realSubdirectories(in: Self.pastureDir)
            .map(\.lastPathComponent)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: — Lifecycle

    func setup() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.pastureDir.path) {
            try? fm.createDirectory(at: Self.pastureDir, withIntermediateDirectories: true)
        }
        reloadObserver = NotificationCenter.default.addObserver(
            forName: pastureDirectoryChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debouncedReload()
            }
        }
        loadFiles()
        startWatching()
    }

    deinit {
        reloadWorkItem?.cancel()
        directorySource?.cancel()
        for source in subdirectorySources.values {
            source.cancel()
        }
        if let obs = reloadObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: — File watching

    private func startWatching() {
        guard directorySource == nil else { return }
        let fd = open(Self.pastureDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directorySource = makeDirectoryWatchSource(fd: fd)
        updateSubdirectoryWatchers()
    }

    func stopWatching() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        for source in subdirectorySources.values {
            source.cancel()
        }
        subdirectorySources.removeAll()
        subdirectoryFDs.removeAll()
    }

    private func updateSubdirectoryWatchers() {
        let currentCollections = Set(collections)
        let watchedCollections = Set(subdirectorySources.keys)

        for name in watchedCollections.subtracting(currentCollections) {
            subdirectorySources[name]?.cancel()
            subdirectorySources.removeValue(forKey: name)
            subdirectoryFDs.removeValue(forKey: name)
        }

        for name in currentCollections.subtracting(watchedCollections) {
            let subdirURL = Self.pastureDir.appendingPathComponent(name)
            let fd = open(subdirURL.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            subdirectoryFDs[name] = fd
            subdirectorySources[name] = makeDirectoryWatchSource(fd: fd)
        }
    }

    private func debouncedReload() {
        reloadWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadFiles()
            }
        }
        reloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    // MARK: — CRUD

    private static func mdFiles(in directory: URL) -> [MDFile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls
            .filter { url in
                guard url.pathExtension.lowercased() == "md" else { return false }
                let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                return rv?.isSymbolicLink != true
            }
            .map { MDFile(url: $0) }
    }

    private static func realSubdirectories(in directory: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls.filter { url in
            let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return rv?.isDirectory == true && rv?.isSymbolicLink != true
        }
    }

    func loadFiles() {
        let pastureDir = Self.pastureDir
        var allMDFiles = Self.mdFiles(in: pastureDir)
        for subdir in Self.realSubdirectories(in: pastureDir) {
            allMDFiles.append(contentsOf: Self.mdFiles(in: subdir))
        }
        files = allMDFiles.sorted { $0.modifiedDate > $1.modifiedDate }
        refreshCollections()
        updateSubdirectoryWatchers()
    }

    func save(file: MDFile) {
        guard Self.isInsidePasture(file.url) else {
            lastError = "Cannot save outside .pasture directory"
            return
        }
        do {
            try file.content.write(to: file.url, atomically: true, encoding: .utf8)
        } catch {
            lastError = "Failed to save \(file.name): \(error.localizedDescription)"
            return
        }
        if let idx = files.firstIndex(of: file) {
            files[idx].modifiedDate = Date()
            files[idx].content = file.content
            files[idx].updateDerivedProperties()
            files.sort { $0.modifiedDate > $1.modifiedDate }
        }
    }

    func create(name: String, content: String, collection: String? = nil) -> MDFile? {
        let cleanName = FilenameSanitizer.sanitize(name)
        guard !cleanName.isEmpty else {
            lastError = "Invalid file name"
            return nil
        }

        guard let targetDir = resolveTargetDirectory(collection: collection) else {
            lastError = "Invalid collection path"
            return nil
        }

        let baseName = cleanName.hasSuffix(".md") ? String(cleanName.dropLast(3)) : cleanName
        let finalURL = Self.deduplicatedURL(baseName: baseName, ext: "md", in: targetDir)
        guard Self.isInsidePasture(finalURL) else {
            lastError = "Invalid file path"
            return nil
        }

        do {
            try content.write(to: finalURL, atomically: true, encoding: .utf8)
            let newFile = MDFile(url: finalURL)
            files.insert(newFile, at: 0)
            return newFile
        } catch {
            lastError = "Failed to create \(cleanName): \(error.localizedDescription)"
            return nil
        }
    }

    func delete(files toDelete: [MDFile]) {
        var deletedURLs: Set<URL> = []
        for file in toDelete {
            guard Self.isInsidePasture(file.url) else { continue }
            do {
                try FileManager.default.removeItem(at: file.url)
                deletedURLs.insert(file.url)
            } catch {
                lastError = "Failed to delete \(file.name): \(error.localizedDescription)"
            }
        }
        files.removeAll { deletedURLs.contains($0.url) }
    }

    func createCollection(name: String) -> Bool {
        let sanitized = FilenameSanitizer.sanitize(name)
        guard !sanitized.isEmpty else { return false }

        let collectionURL = Self.pastureDir.appendingPathComponent(sanitized)
        guard Self.isInsidePasture(collectionURL) else { return false }

        let fm = FileManager.default
        guard !fm.fileExists(atPath: collectionURL.path) else { return false }

        do {
            try fm.createDirectory(at: collectionURL, withIntermediateDirectories: false)
            refreshCollections()
            updateSubdirectoryWatchers()
            return true
        } catch {
            return false
        }
    }

    func moveFile(_ file: MDFile, toCollection collection: String?) {
        guard Self.isInsidePasture(file.url) else { return }

        guard let targetDir = resolveTargetDirectory(collection: collection) else { return }

        let destURL = targetDir.appendingPathComponent(file.url.lastPathComponent)
        guard Self.isInsidePasture(destURL) else { return }
        guard destURL != file.url else { return }

        do {
            try FileManager.default.moveItem(at: file.url, to: destURL)
            loadFiles()
        } catch {
            lastError = "Failed to move \(file.name): \(error.localizedDescription)"
        }
    }

    func deleteCollection(_ name: String) {
        let collectionURL = Self.pastureDir.appendingPathComponent(name)
        guard Self.isInsidePasture(collectionURL) else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: collectionURL.path),
              contents.isEmpty else {
            lastError = "Cannot delete collection '\(name)' — it is not empty"
            return
        }

        do {
            try fm.removeItem(at: collectionURL)
            refreshCollections()
            updateSubdirectoryWatchers()
        } catch {
            lastError = "Failed to delete collection '\(name)': \(error.localizedDescription)"
        }
    }

    // MARK: — Import

    func importFile(from sourceURL: URL, collection: String? = nil) {
        if sourceURL.pathExtension.lowercased() == "pdf" {
            importPDF(from: sourceURL, collection: collection)
            return
        }

        guard let targetDir = resolveTargetDirectory(collection: collection) else {
            lastError = "Invalid collection path"
            return
        }

        let cleanName = FilenameSanitizer.sanitize(sourceURL.deletingPathExtension().lastPathComponent)
        guard !cleanName.isEmpty else {
            lastError = "Invalid file name"
            return
        }
        let ext = sourceURL.pathExtension
        let dest = Self.deduplicatedURL(baseName: cleanName, ext: ext, in: targetDir)
        guard Self.isInsidePasture(dest) else { return }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            let newFile = MDFile(url: dest)
            files.insert(newFile, at: 0)
        } catch {
            lastError = "Failed to import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
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

    func merge(files toMerge: [MDFile], into name: String) -> MDFile? {
        let combined = toMerge.map(\.content).joined(separator: "\n---\n")
        return create(name: name, content: combined)
    }

    // MARK: — Feed

    func feedContext(files toFeed: [MDFile], renderedContents: [URL: String]? = nil) -> String {
        func contextTag(for file: MDFile) -> String {
            let raw = renderedContents?[file.url] ?? file.content
            let body = raw.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
            let safeName = "\(file.name).md".xmlEscapedAttribute
            return "<context name=\"\(safeName)\">\n<![CDATA[\(body)]]>\n</context>"
        }
        if toFeed.count == 1, let f = toFeed.first {
            return contextTag(for: f)
        }
        let inner = toFeed.map { contextTag(for: $0) }.joined(separator: "\n")
        return "<documents>\n\(inner)\n</documents>"
    }

    func totalTokens(for files: [MDFile]) -> Int {
        files.reduce(0) { $0 + $1.tokens }
    }
}
