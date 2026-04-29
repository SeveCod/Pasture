import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import CoreTransferable
import PastureKit

enum FileSortOrder: String, CaseIterable {
    case date = "Date"
    case name = "Name"
}

struct FileTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .plainText) { transfer in
            SentTransferredFile(transfer.url, allowAccessingOriginalFile: true)
        } importing: { received in
            FileTransfer(url: received.file)
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var fm: MDFileManager
    @State private var selectedFiles: Set<MDFile> = []
    @State private var activeFile: MDFile?
    @State private var showPasteSheet = false
    @State private var showMergeSheet = false
    @State private var showTemplateSheet = false
    @State private var showNewCollectionSheet = false
    @State private var showDeleteConfirmation = false
    @State private var filePendingDeletion: MDFile?
    @State private var feedbackMessage: String?
    @State private var templateVariables: [TemplateVariable] = []
    @State private var pendingFeedTargets: [MDFile] = []
    @State private var pendingDestination: ExportDestination?
    @State private var searchText = ""
    @State private var sortOrder: FileSortOrder = .date
    @State private var clipboardClearTrigger: Int = 0
    @State private var exportDestinations: [ExportDestination] = ExportSettings.loadDestinations()

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
                    withAnimation { feedbackMessage = "Collection '\(name)' created" }
                }
            }
        }
        .sheet(isPresented: $showTemplateSheet) {
            TemplateSheet(
                variables: $templateVariables,
                totalTokens: fm.totalTokens(for: pendingFeedTargets),
                onCancel: { showTemplateSheet = false },
                onConfirm: confirmTemplateFeed
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
        .animation(.easeInOut(duration: PastureEffects.animationStandard), value: feedbackMessage)
        .onChange(of: fm.lastError) { _, error in
            if let error {
                withAnimation { feedbackMessage = error }
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
        .task(id: clipboardClearTrigger) {
            guard clipboardClearTrigger > 0 else { return }
            let savedChangeCount = NSPasteboard.general.changeCount
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled,
                  NSPasteboard.general.changeCount == savedChangeCount else { return }
            NSPasteboard.general.clearContents()
            withAnimation { feedbackMessage = "Clipboard cleared" }
        }
    }

    // MARK: — Editor

    @ViewBuilder
    private var editorPanel: some View {
        if let file = activeFile, let idx = fm.files.firstIndex(of: file) {
            VStack(spacing: 0) {
                MarkdownPreviewView(file: fm.files[idx])
                Color.pastureDivider(colorScheme).frame(height: 1)
                editorStatusBar(file: fm.files[idx])
            }
        } else {
            emptyState
        }
    }

    private func editorStatusBar(file: MDFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            Text(file.name + ".md")
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            if let collection = file.collection {
                Text(collection)
                    .font(.pastureStatusBar)
                    .foregroundStyle(Color.pastureTokenBadge)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Color.pastureTokenBadgeBg(colorScheme),
                        in: RoundedRectangle(cornerRadius: PastureEffects.cornerRadiusSmall)
                    )
            }

            if file.hasTemplateVars {
                TemplateBadge(compact: false, colorScheme: colorScheme)
            }

            Spacer()

            Button { openInExternalEditor(file) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10))
                    Text("Open in Editor")
                        .font(.pastureStatusBar)
                }
                .foregroundStyle(Color.pastureAccent)
            }
            .buttonStyle(.plain)
            .help("Open in default editor (Cmd+E)")

            Text("~\(TokenEstimator.formatted(file.tokens)) tokens")
                .font(.pastureTokenCount)
                .foregroundStyle(Color.pastureTokenBadge)
        }
        .padding(.horizontal, PastureLayout.statusBarHPadding)
        .padding(.vertical, PastureLayout.statusBarVPadding)
        .background(Color.pastureStatusBar(colorScheme))
    }

    private var emptyState: some View {
        VStack(spacing: PastureLayout.emptyStateSpacing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: PastureLayout.emptyStateIconSize))
                .foregroundStyle(LinearGradient.pastureBrand)
                .rotationEffect(.degrees(-15))
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                Circle().fill(Color.pastureGrassDark).frame(width: 4, height: 4)
                Circle().fill(Color.pastureGrassMedium).frame(width: 4, height: 4)
                Circle().fill(Color.pastureGrassOrange).frame(width: 4, height: 4)
            }
            .padding(.bottom, 4)

            Text("Feed your AI")
                .font(.pastureEmptyHeading)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            Text("Select a file or paste content from the clipboard")
                .font(.pastureEmptySubtext)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            Text("Use {{VARIABLE}} or {{VAR=default}} for templates")
                .font(.pastureEmptyHint)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme).opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.pastureEditor(colorScheme))
    }

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let msg = feedbackMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.pastureSuccess)
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(Color.pastureTextPrimary(colorScheme))
            }
            .padding(.horizontal, PastureLayout.toastHPadding)
            .padding(.vertical, PastureLayout.toastVPadding)
            .background(.regularMaterial, in: Capsule())
            .pastureShadow(PastureEffects.shadowFloat)
            .padding(.bottom, PastureLayout.toastBottomOffset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: msg) {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: PastureEffects.animationStandard)) {
                    feedbackMessage = nil
                }
            }
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

            Button { showPasteSheet = true } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .help("Create new .md from clipboard")

            Button { importPDFFromDisk() } label: {
                Label("Import PDF", systemImage: "doc.richtext")
            }
            .help("Import a PDF as Markdown")

            if selectedFiles.count > 1 {
                Button { showMergeSheet = true } label: {
                    Label("Merge \(selectedFiles.count)", systemImage: "arrow.triangle.merge")
                }
                .help("Combine \(selectedFiles.count) files into one")
            }

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
        let targets = feedTargets
        guard !targets.isEmpty else { return }

        let allContent = targets.map(\.content).joined(separator: "\n")
        let allVars = TemplateEngine.extractVariables(from: allContent)

        if !allVars.isEmpty {
            templateVariables = allVars
            pendingFeedTargets = targets
            pendingDestination = destination
            showTemplateSheet = true
            return
        }

        deliverFeed(context: fm.feedContext(files: targets), targets: targets, destination: destination)
    }

    private func confirmTemplateFeed() {
        var rendered: [URL: String] = [:]
        for file in pendingFeedTargets {
            rendered[file.url] = TemplateEngine.render(file.content, with: templateVariables)
        }
        deliverFeed(
            context: fm.feedContext(files: pendingFeedTargets, renderedContents: rendered),
            targets: pendingFeedTargets,
            destination: pendingDestination
        )
        showTemplateSheet = false
        pendingFeedTargets = []
        templateVariables = []
        pendingDestination = nil
    }

    private func deliverFeed(context: String, targets: [MDFile], destination: ExportDestination?) {
        let label = targets.count == 1 ? targets[0].name : "\(targets.count) files"
        let tokenLabel = "~\(TokenEstimator.formatted(fm.totalTokens(for: targets))) tokens"

        if let dest = destination {
            do {
                try fm.exportToFile(context, to: dest)
                withAnimation { feedbackMessage = "\(dest.name) \u{2190} \(label) \u{b7} \(tokenLabel)" }
            } catch {
                withAnimation { feedbackMessage = "Export failed: \(error.localizedDescription)" }
            }
        } else {
            copyToClipboard(context, message: "Copied \(label) \u{b7} \(tokenLabel)")
        }
    }

    private func copyToClipboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        clipboardClearTrigger += 1
        withAnimation { feedbackMessage = message }
    }

    private func importPDFFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Select PDF files to import as Markdown"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let created = fm.importPDF(from: url, collection: activeFile?.collection) {
                selectFile(created)
                withAnimation { feedbackMessage = "Imported \(created.name) from PDF" }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let validExtensions: Set<String> = ["md", "pdf"]
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
