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
    @State private var showPasteSheet = false
    @State private var showMergeSheet = false
    @State private var showNewCollectionSheet = false
    @State private var showDeleteConfirmation = false
    @State private var filePendingDeletion: MDFile?
    @State private var searchText = ""
    @State private var sortOrder: FileSortOrder = .date
    @State private var exportDestinations: [ExportDestination] = ExportSettings.loadDestinations()
    @State private var detailMode: DetailMode = .preview
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
                filePendingDeletion: $filePendingDeletion,
                showDeleteConfirmation: $showDeleteConfirmation,
                onDrop: handleDrop
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
        .onReceive(NotificationCenter.default.publisher(for: ExportSettings.didChangeNotification)) { _ in
            exportDestinations = ExportSettings.loadDestinations()
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
        .sheet(isPresented: $feedService.showTemplateSheet) {
            TemplateSheet(
                variables: $feedService.templateVariables,
                totalTokens: fm.totalTokens(for: feedService.pendingFeedTargets),
                onCancel: { feedService.showTemplateSheet = false },
                onConfirm: { feedService.confirmTemplateFeed(fm: fm) }
            )
        }
        .alert("Delete file?",
               isPresented: $showDeleteConfirmation,
               presenting: filePendingDeletion) { file in
            Button("Delete", role: .destructive) { deleteFile(file) }
            Button("Cancel", role: .cancel) { filePendingDeletion = nil }
        } message: { file in
            Text("'\(file.name).md' will be permanently deleted.")
        }
        .overlay(alignment: .bottom) { feedbackOverlay }
        .animation(.easeInOut(duration: PastureEffects.animationStandard), value: feedService.feedbackMessage)
        .onChange(of: fm.lastError) { _, error in
            if let error {
                feedService.showFeedback(error)
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
            AskView(viewModel: askViewModel, feedTargets: feedTargets)
        }
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let msg = feedService.feedbackMessage {
            FeedbackToast(message: msg)
        }
    }

    // MARK: — Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
            .disabled(feedTargets.isEmpty)
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

            FeedButton(
                targets: feedTargets,
                totalTokens: fm.totalTokens(for: feedTargets),
                destinations: exportDestinations,
                onClipboard: { executeFeed(destination: nil) },
                onExport: { dest in executeFeed(destination: dest) }
            )

            Button {
                let previousURL = activeFile?.url
                fm.loadFiles()
                if let url = previousURL {
                    activeFile = fm.files.first { $0.url == url }
                    if let active = activeFile {
                        selectedFiles = [active]
                    }
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload file list from ~/.pasture/")
            .accessibilityLabel("Refresh file list")
        }
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

    private func deleteFile(_ file: MDFile) {
        if activeFile == file { activeFile = nil }
        selectedFiles.remove(file)
        fm.delete(files: [file])
    }

    private func executeFeed(destination: ExportDestination?) {
        feedService.executeFeed(targets: feedTargets, destination: destination, fm: fm)
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
        let context = fm.feedContext(files: targets)
        let panel = NSSavePanel()
        let label = targets.count == 1 ? targets[0].name : "context-\(targets.count)-files"
        panel.nameFieldStringValue = "\(label).md"
        panel.allowedContentTypes = [.plainText]
        panel.message = "Export context as Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try context.write(to: url, atomically: true, encoding: .utf8)
            feedService.showFeedback("Exported to \(url.lastPathComponent)")
        } catch {
            feedService.showFeedback("Export failed: \(error.localizedDescription)")
        }
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
        if let active = activeFile {
            if !newFiles.contains(active) {
                activeFile = newFiles.first { $0.url == active.url }
                    ?? newFiles.first { $0.name == active.name }
            }
        }
        if !selectedFiles.isEmpty {
            let reconciled = selectedFiles.compactMap { selected -> MDFile? in
                if newFiles.contains(selected) { return selected }
                return newFiles.first { $0.url == selected.url }
                    ?? newFiles.first { $0.name == selected.name }
            }
            selectedFiles = Set(reconciled)
        }
    }
}
