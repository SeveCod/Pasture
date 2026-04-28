import Foundation
import Combine
import PDFKit

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
    @Published var searchQuery: String = ""
    @Published var lastError: String?

    nonisolated(unsafe) private var directorySource: (any DispatchSourceFileSystemObject)?
    nonisolated(unsafe) private var watchedFileDescriptor: Int32 = -1
    nonisolated(unsafe) private var reloadWorkItem: DispatchWorkItem?

    static let pastureDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".pasture")
    }()

    var filteredFiles: [MDFile] {
        guard !searchQuery.isEmpty else { return files }
        let q = searchQuery
        return files.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    func setup() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.pastureDir.path) {
            try? fm.createDirectory(at: Self.pastureDir, withIntermediateDirectories: true)
        }
        loadFiles()
        startWatching()
    }

    deinit {
        reloadWorkItem?.cancel()
        directorySource?.cancel()
    }

    private func startWatching() {
        let fd = open(Self.pastureDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    func stopWatching() {
        reloadWorkItem?.cancel()
        reloadWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        watchedFileDescriptor = -1
    }

    private nonisolated func scheduleReload() {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.loadFiles()
            }
        }
        Task { @MainActor [weak self] in
            self?.reloadWorkItem?.cancel()
            self?.reloadWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    func loadFiles() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: Self.pastureDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles
        ) else { return }

        files = urls
            .filter { url in
                guard url.pathExtension.lowercased() == "md" else { return false }
                let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                return resourceValues?.isSymbolicLink != true
            }
            .map { MDFile(url: $0) }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    func save(file: MDFile) {
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

    func create(name: String, content: String) -> MDFile? {
        let cleanName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        let safeName = cleanName.hasSuffix(".md") ? cleanName : "\(cleanName).md"
        let url = Self.pastureDir.appendingPathComponent(safeName)

        guard url.standardizedFileURL.path.hasPrefix(Self.pastureDir.standardizedFileURL.path) else {
            return nil
        }

        var finalURL = url
        var counter = 2
        let baseName = cleanName.hasSuffix(".md") ? String(cleanName.dropLast(3)) : cleanName
        while FileManager.default.fileExists(atPath: finalURL.path) {
            finalURL = Self.pastureDir.appendingPathComponent("\(baseName)-\(counter).md")
            counter += 1
        }

        do {
            try content.write(to: finalURL, atomically: true, encoding: .utf8)
            let newFile = MDFile(url: finalURL)
            files.insert(newFile, at: 0)
            return newFile
        } catch {
            return nil
        }
    }

    func delete(files toDelete: [MDFile]) {
        let pasturePrefix = Self.pastureDir.standardizedFileURL.path
        let urls = Set(toDelete.map(\.url))
        for file in toDelete {
            guard file.url.standardizedFileURL.path.hasPrefix(pasturePrefix) else { continue }
            try? FileManager.default.removeItem(at: file.url)
        }
        files.removeAll { urls.contains($0.url) }
    }

    func importFile(from sourceURL: URL) {
        if sourceURL.pathExtension.lowercased() == "pdf" {
            importPDF(from: sourceURL)
            return
        }
        var dest = Self.pastureDir.appendingPathComponent(sourceURL.lastPathComponent)

        guard dest.standardizedFileURL.path.hasPrefix(Self.pastureDir.standardizedFileURL.path) else { return }

        var counter = 2
        let nameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = Self.pastureDir.appendingPathComponent("\(nameWithoutExt)-\(counter).\(ext)")
            counter += 1
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            let newFile = MDFile(url: dest)
            files.insert(newFile, at: 0)
        } catch {
            // Copy failed — no ghost MDFile
        }
    }

    @discardableResult
    func importPDF(from sourceURL: URL) -> MDFile? {
        guard let doc = PDFDocument(url: sourceURL) else { return nil }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        let text = pages.joined(separator: "\n\n")
        let name = sourceURL.deletingPathExtension().lastPathComponent
        return create(name: name, content: text)
    }

    func merge(files toMerge: [MDFile], into name: String) -> MDFile? {
        let combined = toMerge.map(\.content).joined(separator: "\n---\n")
        return create(name: name, content: combined)
    }

    func feedContext(files toFeed: [MDFile], renderedContents: [URL: String]? = nil) -> String {
        func content(for file: MDFile) -> String {
            renderedContents?[file.url] ?? file.content
        }
        if toFeed.count == 1, let f = toFeed.first {
            let safeName = "\(f.name).md".xmlEscapedAttribute
            return "<context name=\"\(safeName)\">\n\(content(for: f))\n</context>"
        }
        let inner = toFeed.map {
            let safeName = "\($0.name).md".xmlEscapedAttribute
            return "<context name=\"\(safeName)\">\n\(content(for: $0))\n</context>"
        }
        .joined(separator: "\n")
        return "<documents>\n\(inner)\n</documents>"
    }

    func totalTokens(for files: [MDFile]) -> Int {
        files.reduce(0) { $0 + $1.tokens }
    }
}

extension String {
    var xmlEscapedAttribute: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
