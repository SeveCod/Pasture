import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var fm = MDFileManager()
    @State private var selectedFiles: Set<MDFile> = []
    @State private var activeFile: MDFile?
    @State private var showPasteSheet = false
    @State private var showMergeSheet = false
    @State private var showTemplateSheet = false
    @State private var newFileName = ""
    @State private var feedbackMessage: String?
    @State private var templateVariables: [TemplateVariable] = []
    @State private var pendingFeedTargets: [MDFile] = []
    @State private var feedButtonHover = false
    @State private var searchText = ""
    @State private var clipboardClearTrigger: Int = 0

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: PastureLayout.sidebarMinWidth,
                    ideal: PastureLayout.sidebarIdealWidth,
                    max: PastureLayout.sidebarMaxWidth
                )
        } detail: {
            editorPanel
        }
        .toolbar { toolbarContent }
        .onAppear { fm.setup() }
        .onReceive(NotificationCenter.default.publisher(for: .pasteFromClipboard)) { _ in
            triggerPaste()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceSave)) { _ in
            if let file = activeFile, let idx = fm.files.firstIndex(of: file) {
                fm.save(file: fm.files[idx])
            }
        }
        .sheet(isPresented: $showPasteSheet) {
            NameInputSheet(title: "New file from clipboard", actionLabel: "Create") { name in
                let content = NSPasteboard.general.string(forType: .string) ?? ""
                if let created = fm.create(name: name, content: content) {
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
        .sheet(isPresented: $showTemplateSheet) { templateSheet }
        .overlay(alignment: .bottom) { feedbackOverlay }
        .animation(.easeInOut(duration: PastureEffects.animationStandard), value: feedbackMessage)
        .onChange(of: fm.lastError) { _, error in
            if let error {
                withAnimation { feedbackMessage = error }
                fm.lastError = nil
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                fm.searchQuery = newValue
            }
        }
        .onReceive(Just(searchText).debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { value in
            if !value.isEmpty {
                fm.searchQuery = value
            }
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

    // MARK: — Sidebar

    var sidebar: some View {
        VStack(spacing: 0) {
            searchBar
            Color.pastureDivider(colorScheme).frame(height: 1)
            fileList
            Color.pastureDivider(colorScheme).frame(height: 1)
            selectionSummary
        }
        .background(Color.pastureSidebar(colorScheme))
    }

    var searchBar: some View {
        HStack(spacing: PastureLayout.searchBarIconSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                .font(.system(size: 13))
            TextField("Search files…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.pastureSearch)
            if !searchText.isEmpty {
                Button { searchText = "" ; fm.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, PastureLayout.searchBarHPadding)
        .padding(.vertical, PastureLayout.searchBarVPadding)
        .animation(.easeInOut(duration: PastureEffects.animationQuick), value: searchText.isEmpty)
    }

    var fileList: some View {
        List(selection: $selectedFiles) {
            ForEach(fm.filteredFiles) { file in
                FileRow(file: file, colorScheme: colorScheme)
                    .tag(file)
                    .onTapGesture { activeFile = file }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedFiles) { oldVal, newVal in
            if let previous = oldVal.first, oldVal.count == 1,
               let idx = fm.files.firstIndex(of: previous) {
                fm.save(file: fm.files[idx])
            }
            if newVal.count == 1 { activeFile = newVal.first }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    var selectionSummary: some View {
        HStack {
            let count = fm.filteredFiles.count
            let totalTokens = fm.totalTokens(
                for: selectedFiles.isEmpty ? fm.filteredFiles : Array(selectedFiles)
            )
            let label = selectedFiles.isEmpty ? "\(count) files" : "\(selectedFiles.count) selected"

            Text(label)
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .semibold))
                Text("~\(TokenEstimator.formatted(totalTokens)) tokens")
                    .font(.pastureSummary)
            }
            .foregroundStyle(Color.pastureTokenBadge)
        }
        .padding(.horizontal, PastureLayout.summaryBarHPadding)
        .padding(.vertical, PastureLayout.summaryBarVPadding)
    }

    // MARK: — Editor

    @ViewBuilder
    var editorPanel: some View {
        if let file = activeFile, let idx = fm.files.firstIndex(of: file) {
            VStack(spacing: 0) {
                EditorView(file: $fm.files[idx], onSave: { fm.save(file: fm.files[idx]) })
                    .background(Color.pastureEditor(colorScheme))
                Color.pastureDivider(colorScheme).frame(height: 1)
                editorStatusBar(file: fm.files[idx])
            }
        } else {
            emptyState
        }
    }

    func editorStatusBar(file: MDFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            Text(file.name + ".md")
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            if file.hasTemplateVars {
                TemplateBadge(compact: false, colorScheme: colorScheme)
            }

            Spacer()

            Text("~\(TokenEstimator.formatted(file.tokens)) tokens")
                .font(.pastureTokenCount)
                .foregroundStyle(Color.pastureTokenBadge)
        }
        .padding(.horizontal, PastureLayout.statusBarHPadding)
        .padding(.vertical, PastureLayout.statusBarVPadding)
        .background(Color.pastureStatusBar(colorScheme))
    }

    var emptyState: some View {
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
    var feedbackOverlay: some View {
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
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { triggerPaste() } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .help("Create new .md from clipboard (⌘⇧V)")

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

            feedButton

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

    var feedButton: some View {
        let targets = feedTargets
        let tokens = fm.totalTokens(for: targets)
        let isDisabled = targets.isEmpty

        return Button { feedClaude() } label: {
            HStack(spacing: 5) {
                Image(systemName: "leaf.fill")
                    .rotationEffect(.degrees(15))
                Text("Feed \(TokenEstimator.formatted(tokens))")
                    .font(.pastureToolbarLabel)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, PastureLayout.feedButtonHPadding)
            .padding(.vertical, PastureLayout.feedButtonVPadding)
            .background(
                isDisabled
                    ? AnyShapeStyle(Color.pastureTextTertiaryLight.opacity(0.3))
                    : AnyShapeStyle(feedButtonHover ? LinearGradient.pastureFeedButtonHover : LinearGradient.pastureFeedButton)
            )
            .clipShape(RoundedRectangle(cornerRadius: PastureLayout.feedButtonRadius))
            .scaleEffect(feedButtonHover && !isDisabled ? 1.02 : 1.0)
            .animation(.easeInOut(duration: PastureEffects.animationQuick), value: feedButtonHover)
        }
        .buttonStyle(.plain)
        .onHover { hovering in feedButtonHover = hovering }
        .disabled(isDisabled)
        .help("Copy wrapped in <context> tags for Claude")
    }

    // MARK: — Sheets

    var templateSheet: some View {
        VStack(spacing: PastureLayout.sheetSpacing) {
            Text("Fill template variables")
                .font(.pastureSheetHeading)
            Text("These placeholders will be replaced before copying")
                .font(.pastureSheetSubheading)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach($templateVariables) { $variable in
                        HStack {
                            Text("{{\(variable.name)}}")
                                .font(.pastureTemplateVar)
                                .foregroundStyle(Color.pastureTemplate)
                                .frame(width: PastureLayout.templateVarLabelWidth, alignment: .trailing)
                            TextField(
                                variable.defaultValue.isEmpty ? "Value" : variable.defaultValue,
                                text: $variable.value
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: PastureLayout.templateVarInputWidth)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Text("~\(TokenEstimator.formatted(fm.totalTokens(for: pendingFeedTargets))) tokens")
                .font(.pastureTokenBadge)
                .foregroundStyle(Color.pastureTokenBadge)

            HStack(spacing: PastureLayout.sheetButtonSpacing) {
                Button("Cancel") { showTemplateSheet = false }
                    .keyboardShortcut(.cancelAction)

                Button { confirmTemplateFeed() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11))
                        Text("Feed")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(LinearGradient.pastureFeedButton)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PastureLayout.sheetPadding)
        .frame(minWidth: PastureLayout.templateSheetMinWidth)
    }

    // MARK: — Actions

    var feedTargets: [MDFile] {
        if selectedFiles.count > 1 {
            return fm.files.filter { selectedFiles.contains($0) }
        } else if let f = activeFile {
            return [f]
        }
        return []
    }

    func selectFile(_ file: MDFile) {
        activeFile = file
        selectedFiles = [file]
    }

    func triggerPaste() {
        newFileName = ""
        showPasteSheet = true
    }

    func feedClaude() {
        let targets = feedTargets
        guard !targets.isEmpty else { return }

        let allContent = targets.map(\.content).joined(separator: "\n")
        let allVars = TemplateEngine.extractVariables(from: allContent)

        if !allVars.isEmpty {
            templateVariables = allVars
            pendingFeedTargets = targets
            showTemplateSheet = true
            return
        }

        copyToClipboard(fm.feedContext(files: targets),
                        message: "Copied \(targets.count == 1 ? targets[0].name : "\(targets.count) files") · ~\(TokenEstimator.formatted(fm.totalTokens(for: targets))) tokens")
    }

    func confirmTemplateFeed() {
        var rendered: [URL: String] = [:]
        for file in pendingFeedTargets {
            rendered[file.url] = TemplateEngine.render(file.content, with: templateVariables)
        }
        let count = pendingFeedTargets.count
        copyToClipboard(fm.feedContext(files: pendingFeedTargets, renderedContents: rendered),
                        message: "Fed \(count == 1 ? pendingFeedTargets[0].name : "\(count) files") with \(templateVariables.count) variables")
        showTemplateSheet = false
        pendingFeedTargets = []
        templateVariables = []
    }

    func copyToClipboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        clipboardClearTrigger += 1
        withAnimation { feedbackMessage = message }
    }

    func importPDFFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Select PDF files to import as Markdown"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let created = fm.importPDF(from: url) {
                selectFile(created)
                withAnimation { feedbackMessage = "Imported \(created.name) from PDF" }
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
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
                    fm.importFile(from: url)
                }
            }
        }
        return hasValidProvider
    }
}

// MARK: — Extracted Views: EditorView.swift, FileRow.swift, NameInputSheet.swift, TemplateBadge.swift
