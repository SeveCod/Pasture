import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import PastureKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var fm: MDFileManager
    @State private var selectedFiles: Set<MDFile> = []
    @State private var activeFile: MDFile?
    @State private var showNewFileSheet = false
    @State private var showPasteSheet = false
    @State private var showMergeSheet = false
    @State private var showNewCollectionSheet = false
    @State private var showDeleteConfirmation = false
    @State private var filesPendingDeletion: [MDFile] = []
    @State private var searchText = ""
    @State private var sortOrder: FileSortOrder = .date
    @State private var exportDestinations: [ExportDestination] = ExportSettings.loadDestinations()
    @State private var detailMode: DetailMode = .preview
    @State private var presets: [SelectionPreset] = SelectionPresetStore.load()
    @State private var showSavePresetSheet = false
    @State private var presetPendingRename: SelectionPreset?
    @State private var presetPendingDeletion: SelectionPreset?
    @State private var presetOverwritePending: (name: String, paths: [String])?
    @StateObject private var askViewModel = AskViewModel()
    @StateObject private var feedService = FeedService()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                fm: fm,
                selectedFiles: $selectedFiles,
                activeFile: $activeFile,
                searchText: $searchText,
                sortOrder: $sortOrder,
                filesPendingDeletion: $filesPendingDeletion,
                showDeleteConfirmation: $showDeleteConfirmation,
                onDrop: handleDrop,
                onOpenInEditor: openInExternalEditor
            )
            .navigationSplitViewColumnWidth(
                min: PastureLayout.sidebarMinWidth,
                ideal: PastureLayout.sidebarIdealWidth,
                max: PastureLayout.sidebarMaxWidth
            )
        } detail: {
            editorPanel
        }
        .toolbar { toolbarContent }
        .onReceive(NotificationCenter.default.publisher(for: .newFile)) { _ in
            showNewFileSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteFromClipboard)) { _ in
            showPasteSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openInEditor)) { _ in
            if let file = activeFile {
                openInExternalEditor(file)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAskMode)) { _ in
            withAnimation(.easeInOut(duration: PastureEffects.animationStandard)) {
                detailMode = detailMode == .preview ? .ask : .preview
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncAllPacks)) { _ in
            Task {
                let summary = await PackSyncRunner.syncAll()
                feedService.showFeedback(summary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshSources)) { _ in
            let summary = fm.refreshSources()
            feedService.showFeedback(summary.message, isError: summary.sourcesFailed > 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: ExportSettings.didChangeNotification)) { _ in
            exportDestinations = ExportSettings.loadDestinations()
        }
        .onReceive(NotificationCenter.default.publisher(for: SelectionPresetStore.didChangeNotification)) { _ in
            presets = SelectionPresetStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .performSearch)) { note in
            // v1.9 — pasture://search?q=…: el debounce existente propaga a fm.searchQuery.
            if let query = note.object as? String {
                searchText = query
            }
        }
        .modifier(presetSheetsAndAlerts)
        .sheet(isPresented: $showNewFileSheet) {
            NameInputSheet(title: "New file", actionLabel: "Create") { name in
                // Nace en la colección activa, igual que una nota pegada.
                // Los fallos de `create` llegan al usuario por `fm.lastError`.
                if let created = fm.create(name: name, content: "", collection: activeFile?.collection) {
                    selectFile(created)
                    // `created.name` y no `name`: la deduplicación puede haberlo cambiado.
                    feedService.showFeedback("Created '\(created.name).md'")
                }
            }
        }
        .sheet(isPresented: $showPasteSheet) {
            NameInputSheet(title: "New file from clipboard", actionLabel: "Create") { name in
                let content = NSPasteboard.general.string(forType: .string) ?? ""
                if let created = fm.create(name: name, content: content, collection: activeFile?.collection) {
                    selectFile(created)
                }
            }
        }
        .sheet(isPresented: $showMergeSheet) {
            NameInputSheet(title: "Merge \(selectedFiles.count) files", actionLabel: "Merge") { name in
                let ordered = fm.files.filter { selectedFiles.contains($0) }
                if let merged = fm.merge(files: ordered, into: name) {
                    selectFile(merged)
                }
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NameInputSheet(title: "New collection", actionLabel: "Create") { name in
                if fm.createCollection(name: name) {
                    feedService.showFeedback("Collection '\(name)' created")
                }
            }
        }
        .alert(deleteAlertTitle,
               isPresented: $showDeleteConfirmation,
               presenting: filesForDeletionAlert) { files in
            Button("Delete", role: .destructive) { deleteFiles(files) }
            Button("Cancel", role: .cancel) { filesPendingDeletion = [] }
        } message: { files in
            Text(Self.deleteConfirmationMessage(for: files))
        }
        .feedChrome(feedService, fm: fm)
        .onChange(of: fm.lastError) { _, error in
            if let error {
                feedService.showFeedback(error, isError: true)
                fm.lastError = nil
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { fm.searchQuery = newValue }
        }
        .onChange(of: fm.files) { _, newFiles in
            reconcileSelection(with: newFiles)
        }
        .onReceive(Just(searchText).debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { value in
            if !value.isEmpty { fm.searchQuery = value }
        }
    }

    // MARK: — Editor

    @ViewBuilder
    private var editorPanel: some View {
        switch detailMode {
        case .preview:
            if let file = activeFile, let idx = fm.files.firstIndex(of: file) {
                VStack(spacing: 0) {
                    MarkdownPreviewView(file: fm.files[idx])
                    Color.pastureDivider(colorScheme).frame(height: 1)
                    EditorStatusBar(file: fm.files[idx]) { openInExternalEditor(fm.files[idx]) }
                }
            } else {
                PastureEmptyState()
            }
        case .ask:
            AskView(viewModel: askViewModel, feedTargets: feedTargets, feedService: feedService)
        }
    }

    // MARK: — Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            let targets = feedTargets

            Button { showNewFileSheet = true } label: {
                Label("New File", systemImage: "square.and.pencil")
            }
            .help("Create a new empty note")
            .accessibilityLabel("New file")

            Button { showNewCollectionSheet = true } label: {
                Label("New Collection", systemImage: "folder.badge.plus")
            }
            .help("Create a new collection")
            .accessibilityLabel("New Collection")

            Button { showPasteSheet = true } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .help("Create new .md from clipboard")
            .accessibilityLabel("Paste from clipboard")
            .accessibilityHint("Creates a new Markdown file from clipboard content")

            Button { importFromDisk() } label: {
                Label("Import", systemImage: "doc.badge.plus")
            }
            .help("Import files (PDF, CSV, DOCX)")
            .accessibilityLabel("Import files")
            .accessibilityHint("Import PDF, CSV, or DOCX files as Markdown")

            Button { scanFolderFromDisk() } label: {
                Label("Scan Folder", systemImage: "folder.badge.questionmark")
            }
            .help("Scan a folder for .md files and import them")
            .accessibilityLabel("Scan folder")
            .accessibilityHint("Scan a folder for Markdown files and import them")

            Button { exportFeedToDisk() } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(targets.isEmpty)
            .help("Export context as .md to any location")
            .accessibilityLabel("Export context")

            if selectedFiles.count > 1 {
                Button { showMergeSheet = true } label: {
                    Label("Merge \(selectedFiles.count)", systemImage: "arrow.triangle.merge")
                }
                .help("Combine \(selectedFiles.count) files into one")
                .accessibilityLabel("Merge \(selectedFiles.count) files")
                .accessibilityHint("Combine selected files into a single file")
            }

            Button {
                withAnimation(.easeInOut(duration: PastureEffects.animationStandard)) {
                    detailMode = detailMode == .preview ? .ask : .preview
                }
            } label: {
                Label("Ask", systemImage: detailMode == .ask
                      ? "bubble.left.and.text.bubble.right.fill"
                      : "bubble.left.and.text.bubble.right")
            }
            .help("Toggle Ask mode (Cmd+Shift+A)")
            .accessibilityLabel("Toggle Ask mode")
            .accessibilityValue(detailMode == .ask ? "Active" : "Inactive")

            presetMenu

            FeedButton(
                targets: targets,
                totalTokens: fm.totalTokens(for: targets),
                destinations: exportDestinations,
                onClipboard: { executeFeed(destination: nil) },
                onExport: { dest in executeFeed(destination: dest) }
            )

            Button {
                // Async reload; selection is reconciled by onChange(of: fm.files)
                fm.loadFiles()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload file list from ~/.pasture/")
            .accessibilityLabel("Refresh file list")
        }
    }

    // MARK: — Presets sheets & alerts

    /// Agrupa las sheets/alerts de presets en un modificador propio para aligerar
    /// el `body` (el type-checker se atraganta si están todas inline).
    private var presetSheetsAndAlerts: some ViewModifier {
        PresetSheetsAndAlerts(
            showSavePresetSheet: $showSavePresetSheet,
            presetPendingRename: $presetPendingRename,
            presetPendingDeletion: $presetPendingDeletion,
            presetOverwritePending: $presetOverwritePending,
            onSave: { savePreset(named: $0) },
            onRename: { id, newName in
                let clean = SelectionPreset.sanitizedName(newName)
                guard !clean.isEmpty else { return }
                SelectionPresetStore.rename(id: id, to: clean)
            },
            onDelete: { SelectionPresetStore.delete(id: $0) },
            onOverwrite: { overwritePreset($0.name, paths: $0.paths) }
        )
    }

    // MARK: — Presets menu

    private var presetMenu: some View {
        Menu {
            Button {
                showSavePresetSheet = true
            } label: {
                Label("Save Selection as Preset\u{2026}", systemImage: "bookmark")
            }
            .disabled(selectionForPreset.isEmpty)

            if !presets.isEmpty {
                Divider()
                ForEach(presets) { preset in
                    // UX-6: el clic en el nombre aplica el preset (como en la barra
                    // de menús); la gestión queda en el menú de mantenido.
                    Menu(preset.name) {
                        Button("Rename\u{2026}") { presetPendingRename = preset }
                        Divider()
                        Button("Delete\u{2026}", role: .destructive) {
                            presetPendingDeletion = preset
                        }
                    } primaryAction: {
                        applyPreset(preset)
                    }
                }
            }
        } label: {
            Label("Presets", systemImage: "bookmark.fill")
        }
        .help("Save and apply selection presets")
        .accessibilityLabel("Selection presets")
    }

    // MARK: — Actions

    private var feedTargets: [MDFile] {
        if selectedFiles.count > 1 {
            return fm.files.filter { selectedFiles.contains($0) }
        } else if let f = activeFile {
            return [f]
        }
        return []
    }

    private func selectFile(_ file: MDFile) {
        activeFile = file
        selectedFiles = [file]
    }

    /// Datos del alert de borrado: nil cuando no hay nada pendiente.
    private var filesForDeletionAlert: [MDFile]? {
        filesPendingDeletion.isEmpty ? nil : filesPendingDeletion
    }

    /// Título del alert de borrado, en singular o plural. Se lee del estado y no del
    /// parámetro del closure: el título se evalúa al construir el cuerpo de la vista.
    private var deleteAlertTitle: String {
        let count: Int = filesPendingDeletion.count
        return count > 1 ? "Delete \(count) files?" : "Delete file?"
    }

    /// Texto del alert de borrado, en singular o plural.
    /// Extraído del cuerpo de la vista: en línea el type-checker no lo resuelve.
    private static func deleteConfirmationMessage(for files: [MDFile]) -> String {
        if files.count == 1 {
            let name: String = files[0].name
            return "'\(name).md' will be moved to the Trash."
        }
        let count: Int = files.count
        return "\(count) files will be moved to the Trash."
    }

    private func deleteFiles(_ files: [MDFile]) {
        if let active = activeFile, files.contains(active) { activeFile = nil }
        selectedFiles.subtract(files)
        fm.delete(files: files)
        filesPendingDeletion = []
    }

    private func executeFeed(destination: ExportDestination?) {
        feedService.executeFeed(targets: feedTargets, destination: destination, fm: fm)
    }

    // MARK: — Presets (F2)

    /// Ficheros actualmente seleccionados (selección múltiple o fichero activo).
    private var selectionForPreset: [MDFile] {
        if !selectedFiles.isEmpty {
            return fm.files.filter { selectedFiles.contains($0) }
        } else if let f = activeFile {
            return [f]
        }
        return []
    }

    private func savePreset(named rawName: String) {
        let name = SelectionPreset.sanitizedName(rawName)
        guard !name.isEmpty else { return }
        let paths = fm.relativePaths(for: selectionForPreset)
        guard !paths.isEmpty else {
            feedService.showFeedback("No selection to save", isError: true)
            return
        }
        if SelectionPresetStore.preset(named: name) != nil {
            // HU-4: confirmar sobrescritura de un nombre duplicado.
            presetOverwritePending = (name: name, paths: paths)
            return
        }
        SelectionPresetStore.upsert(SelectionPreset(name: name, relativePaths: paths))
        feedService.showFeedback("Saved preset '\(name)'")
    }

    private func overwritePreset(_ name: String, paths: [String]) {
        presetOverwritePending = nil
        if let existing = SelectionPresetStore.preset(named: name) {
            SelectionPresetStore.upsert(
                SelectionPreset(id: existing.id, name: name, relativePaths: paths, createdAt: existing.createdAt)
            )
        } else {
            SelectionPresetStore.upsert(SelectionPreset(name: name, relativePaths: paths))
        }
        feedService.showFeedback("Updated preset '\(name)'")
    }

    private func applyPreset(_ preset: SelectionPreset) {
        let (files, missingPaths) = fm.resolve(preset)
        selectedFiles = Set(files)
        if files.count == 1 { activeFile = files.first }
        if let missing = SelectionPreset.missingFilesMessage(missingPaths: missingPaths) {
            feedService.showFeedback("Applied '\(preset.name)' — \(missing)")
        } else {
            feedService.showFeedback("Applied '\(preset.name)'")
        }
    }

    private func importFromDisk() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.pdf, .commaSeparatedText]
        if let docxType = UTType(filenameExtension: "docx") { types.append(docxType) }
        if let docType = UTType(filenameExtension: "doc") { types.append(docType) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.message = "Select files to import as Markdown (PDF, CSV, DOCX)"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let created = fm.importFile(from: url, collection: activeFile?.collection) {
                selectFile(created)
                feedService.showFeedback("Imported \(created.name)")
            }
        }
    }

    private func scanFolderFromDisk() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to scan for .md files"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let count = fm.scanFolder(at: url)
        if count > 0 {
            feedService.showFeedback("Imported \(count) file\(count == 1 ? "" : "s") from \(url.lastPathComponent)")
        }
    }

    private func exportFeedToDisk() {
        let targets = feedTargets
        guard !targets.isEmpty else { return }
        let panel = NSSavePanel()
        let label = targets.count == 1 ? targets[0].name : "context-\(targets.count)-files"
        let format = ExportSettings.fileFormat()
        panel.nameFieldStringValue = "\(label).\(format.fileExtension)"
        panel.allowedContentTypes = format.allowedContentTypes
        panel.message = "Export feed context"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // El contenido lo produce FeedService, que aplica la sustitución de plantillas
        // y el escaneo de secretos ANTES de escribir (auditoría 2.1: antes esta ruta
        // escribía a disco sin ninguna de las dos guardas).
        feedService.exportToDisk(targets: targets, url: url, fm: fm)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let validExtensions: Set<String> = ["md", "pdf", "csv", "docx", "doc"]
        var hasValidProvider = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier("public.file-url") else { continue }
            hasValidProvider = true
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      validExtensions.contains(url.pathExtension.lowercased()) else { return }
                DispatchQueue.main.async {
                    fm.importFile(from: url, collection: activeFile?.collection)
                }
            }
        }
        return hasValidProvider
    }

    private func openInExternalEditor(_ file: MDFile) {
        guard MDFileManager.isInsidePasture(file.url) else { return }
        NSWorkspace.shared.open(file.url)
    }

    private func reconcileSelection(with newFiles: [MDFile]) {
        // Reconcile by URL only. A name-based fallback could silently select the
        // wrong file after an external rename (names are not guaranteed unique).
        if let active = activeFile, !newFiles.contains(active) {
            activeFile = newFiles.first { $0.url == active.url }
        }
        if !selectedFiles.isEmpty {
            let reconciled = selectedFiles.compactMap { selected -> MDFile? in
                if newFiles.contains(selected) { return selected }
                return newFiles.first { $0.url == selected.url }
            }
            selectedFiles = Set(reconciled)
        }
    }
}

// MARK: — Preset sheets & alerts (extraído del body para el type-checker)

private struct PresetSheetsAndAlerts: ViewModifier {
    @Binding var showSavePresetSheet: Bool
    @Binding var presetPendingRename: SelectionPreset?
    @Binding var presetPendingDeletion: SelectionPreset?
    @Binding var presetOverwritePending: (name: String, paths: [String])?
    let onSave: (String) -> Void
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void
    let onOverwrite: ((name: String, paths: [String])) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showSavePresetSheet) {
                NameInputSheet(title: "Save selection as preset", actionLabel: "Save") { name in
                    onSave(name)
                }
            }
            .sheet(item: $presetPendingRename) { preset in
                NameInputSheet(
                    title: "Rename preset '\(preset.name)'",
                    actionLabel: "Rename",
                    initialName: preset.name
                ) { newName in
                    onRename(preset.id, newName)
                }
            }
            .alert(
                "Overwrite preset?",
                isPresented: Binding(
                    get: { presetOverwritePending != nil },
                    set: { if !$0 { presetOverwritePending = nil } }
                ),
                presenting: presetOverwritePending
            ) { pending in
                Button("Cancel", role: .cancel) { presetOverwritePending = nil }
                Button("Overwrite", role: .destructive) { onOverwrite(pending) }
            } message: { pending in
                Text("A preset named '\(pending.name)' already exists. Overwrite it?")
            }
            .alert(
                "Delete preset?",
                isPresented: Binding(
                    get: { presetPendingDeletion != nil },
                    set: { if !$0 { presetPendingDeletion = nil } }
                ),
                presenting: presetPendingDeletion
            ) { preset in
                Button("Delete", role: .destructive) {
                    onDelete(preset.id)
                    presetPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { presetPendingDeletion = nil }
            } message: { preset in
                Text("The preset '\(preset.name)' will be deleted. Your files in ~/.pasture/ are not affected — a preset is only a reference.")
            }
    }
}
