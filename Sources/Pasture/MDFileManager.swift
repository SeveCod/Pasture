import Foundation
import Combine
import PastureKit

private let pastureDirURL: URL = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".pasture")
}()

extension MDFile {
    var collection: String? {
        collection(relativeTo: pastureDirURL)
    }
}

@MainActor
final class MDFileManager: ObservableObject {
    /// Invariant: always sorted by modifiedDate descending (FileLibrary.load
    /// returns it sorted; save() re-sorts after updating). SidebarView's date
    /// mode relies on this and returns the array as-is.
    @Published var files: [MDFile] = [] {
        didSet { updateFilteredFiles() }
    }
    @Published var collections: [String] = []
    @Published var searchQuery: String = "" {
        didSet { if searchQuery != oldValue { updateFilteredFiles() } }
    }
    @Published var lastError: String?

    /// Cached search result — recomputed only when `files` or `searchQuery` change,
    /// not on every SwiftUI body evaluation.
    @Published private(set) var filteredFiles: [MDFile] = []

    private let watcher = DirectoryWatcher()
    private var loadTask: Task<Void, Never>?

    static let pastureDir: URL = pastureDirURL

    private func updateFilteredFiles() {
        filteredFiles = searchQuery.isEmpty ? files : files.filter { $0.matches(query: searchQuery) }
    }

    // MARK: — Helpers

    static func isInsidePasture(_ url: URL) -> Bool {
        PathValidator.isInside(target: url, base: pastureDir)
    }

    func resolveTargetDirectory(collection: String?) -> URL? {
        guard let collection else { return Self.pastureDir }
        let collectionDir = Self.pastureDir.appendingPathComponent(collection)
        guard Self.isInsidePasture(collectionDir) else { return nil }
        try? FileManager.default.createDirectory(at: collectionDir, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: collectionDir.path, isDirectory: &isDir), isDir.boolValue else {
            lastError = "Cannot create collection directory '\(collection)'"
            return nil
        }
        return collectionDir
    }

    private func refreshCollections(from subdirs: [URL]) {
        collections = subdirs
            .map(\.lastPathComponent)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func refreshCollections() {
        refreshCollections(from: FileLibrary.realSubdirectories(in: Self.pastureDir))
    }

    // MARK: — Lifecycle

    init() {
        setup()
    }

    func setup() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Self.pastureDir.path) {
            try? fm.createDirectory(at: Self.pastureDir, withIntermediateDirectories: true)
        }
        // Verificamos el resultado como en resolveTargetDirectory: si el vault raíz no
        // se pudo crear (permisos, disco lleno, home de solo lectura), el watcher y
        // loadFiles fallarían en silencio y la app se vería vacía sin ninguna pista.
        // Fijamos lastError para que el fallo sea visible.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: Self.pastureDir.path, isDirectory: &isDir), isDir.boolValue else {
            lastError = "Cannot create the Pasture directory at \(Self.pastureDir.path)"
            return
        }
        watcher.onChange = { [weak self] in
            self?.loadFiles()
            self?.autoResyncPacks()
        }
        watcher.watchRoot(Self.pastureDir)
        loadFiles()
    }

    // MARK: — CRUD

    /// Reloads the library asynchronously: disk I/O runs off the main actor
    /// (`FileLibrary.load` is nonisolated), results are applied back on it.
    /// A new call cancels any in-flight reload.
    func loadFiles() {
        loadTask?.cancel()
        let dir = Self.pastureDir
        loadTask = Task { [weak self] in
            let result = await FileLibrary.load(at: dir)
            guard !Task.isCancelled else { return }
            self?.apply(result)
        }
    }

    /// Context Compiler (v1.6): al cambiar el vault, recompila los packs con
    /// `autoResync` activado. Defaults seguros (`force=false`): un destino en
    /// conflicto NUNCA se sobrescribe automáticamente (AC#9). Silencioso y
    /// fire-and-forget — no molesta con toasts si no hay packs opt-in. Pasture
    /// escribe en repos (fuera del vault), así que no re-dispara el watcher.
    private func autoResyncPacks() {
        guard PackStore.load().contains(where: \.autoResync) else { return }
        Task { _ = await PackSyncRunner.syncAll(autoResyncOnly: true) }
    }

    private func apply(_ result: FileLibrary.LoadResult) {
        files = result.files
        refreshCollections(from: result.subdirectories)
        watcher.updateSubdirectories(names: collections, under: Self.pastureDir)
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
        let finalURL = FileLibrary.deduplicatedURL(baseName: baseName, ext: "md", in: targetDir)
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

    /// Renames a file in place (same collection). Returns the renamed file, or
    /// the original when the name is unchanged; `nil` on failure.
    @discardableResult
    func rename(file: MDFile, to newName: String) -> MDFile? {
        guard Self.isInsidePasture(file.url) else { return nil }
        let clean = FilenameSanitizer.sanitize(newName)
        guard !clean.isEmpty else {
            lastError = "Invalid file name"
            return nil
        }
        let baseName = clean.hasSuffix(".md") ? String(clean.dropLast(3)) : clean
        guard baseName != file.name else { return file }

        let directory = file.url.deletingLastPathComponent()
        let destURL = FileLibrary.deduplicatedURL(baseName: baseName, ext: "md", in: directory)
        guard Self.isInsidePasture(destURL) else { return nil }

        do {
            try FileManager.default.moveItem(at: file.url, to: destURL)
            let renamed = MDFile(url: destURL)
            if let idx = files.firstIndex(of: file) {
                files[idx] = renamed
            }
            return renamed
        } catch {
            lastError = "Failed to rename \(file.name): \(error.localizedDescription)"
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
            watcher.updateSubdirectories(names: collections, under: Self.pastureDir)
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

    /// Renames a collection directory. The full library reloads afterwards
    /// because every contained file's URL changes.
    @discardableResult
    func renameCollection(_ name: String, to newName: String) -> Bool {
        let clean = FilenameSanitizer.sanitize(newName)
        guard !clean.isEmpty, clean != name else { return false }

        let sourceURL = Self.pastureDir.appendingPathComponent(name)
        let destURL = Self.pastureDir.appendingPathComponent(clean)
        guard Self.isInsidePasture(sourceURL), Self.isInsidePasture(destURL) else { return false }
        guard !FileManager.default.fileExists(atPath: destURL.path) else {
            lastError = "A collection named '\(clean)' already exists"
            return false
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            loadFiles()
            return true
        } catch {
            lastError = "Failed to rename collection '\(name)': \(error.localizedDescription)"
            return false
        }
    }

    func deleteCollection(_ name: String) {
        let collectionURL = Self.pastureDir.appendingPathComponent(name)
        guard Self.isInsidePasture(collectionURL) else { return }

        let contents: [URL]
        do {
            // visibleContents skips hidden files: a .DS_Store must not block
            // deleting a visually empty collection
            contents = try FileLibrary.visibleContents(of: collectionURL)
        } catch {
            lastError = "Cannot read collection '\(name)': \(error.localizedDescription)"
            return
        }
        guard contents.isEmpty else {
            lastError = "Cannot delete collection '\(name)' — it is not empty"
            return
        }

        do {
            try FileManager.default.removeItem(at: collectionURL)
            refreshCollections()
            watcher.updateSubdirectories(names: collections, under: Self.pastureDir)
        } catch {
            lastError = "Failed to delete collection '\(name)': \(error.localizedDescription)"
        }
    }

    // MARK: — Feed

    func feedContext(files toFeed: [MDFile], renderedContents: [URL: String]? = nil) -> String {
        let entries = toFeed.map { file in
            ContextBuilder.FileEntry(
                name: file.name,
                content: renderedContents?[file.url] ?? file.content
            )
        }
        return ContextBuilder.build(files: entries, format: FeedFormatSettings.feedFormat())
    }

    func totalTokens(for files: [MDFile]) -> Int {
        files.reduce(0) { $0 + $1.tokens }
    }

    // MARK: — Export

    func exportToFile(_ context: String, to destination: ExportDestination) throws {
        try context.write(to: destination.url, atomically: true, encoding: .utf8)
    }

    // MARK: — Presets (F2)

    /// Resuelve un preset a los MDFile existentes en la librería + las rutas
    /// ausentes (no existen en disco o fueron descartadas por SEC-9). Expone los
    /// paths concretos para un toast accionable (M-3). No borra el preset
    /// (decisión de producto): degrada con gracia.
    func resolve(_ preset: SelectionPreset) -> (files: [MDFile], missingPaths: [String]) {
        let resolution = PresetResolver.resolve(relativePaths: preset.relativePaths, base: Self.pastureDir)
        let byURL = Dictionary(uniqueKeysWithValues: files.map { ($0.url.standardizedFileURL, $0) })
        var resolved: [MDFile] = []
        for url in resolution.urls {
            if let file = byURL[url] {
                resolved.append(file)
            }
        }
        let existing = Set(files.map { $0.url.standardizedFileURL })
        let missing = PresetResolver.missingPaths(
            relativePaths: preset.relativePaths,
            base: Self.pastureDir,
            existing: existing
        )
        return (resolved, missing)
    }

    /// Construye las rutas relativas de una selección actual, para "Guardar como
    /// preset". Descarta ficheros fuera de `~/.pasture/` (no deberían existir).
    func relativePaths(for selection: [MDFile]) -> [String] {
        selection.compactMap { PresetResolver.relativePath(for: $0.url, base: Self.pastureDir) }
    }
}
