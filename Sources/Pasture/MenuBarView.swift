import SwiftUI
import AppKit
import PastureKit

struct MenuBarView: View {
    @EnvironmentObject private var fm: MDFileManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @State private var selectedFiles: Set<MDFile> = []
    @State private var searchText = ""
    @State private var feedbackMessage: String?
    @State private var showTemplateSheet = false
    @State private var templateVariables: [TemplateVariable] = []
    @State private var pendingFeedTargets: [MDFile] = []
    @State private var pendingDestination: ExportDestination?
    @State private var clipboardClearTrigger: Int = 0
    @State private var exportDestinations: [ExportDestination] = ExportSettings.loadDestinations()

    private var filteredFiles: [MDFile] {
        guard !searchText.isEmpty else { return fm.files }
        let q = searchText
        return fm.files.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    private var feedTargets: [MDFile] {
        fm.files.filter { selectedFiles.contains($0) }
    }

    private var totalTokens: Int {
        fm.totalTokens(for: feedTargets)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            fileList
            Divider()
            footer
        }
        .frame(width: 320)
        .overlay(alignment: .bottom) { feedbackOverlay }
        .sheet(isPresented: $showTemplateSheet) {
            TemplateSheet(
                variables: $templateVariables,
                totalTokens: totalTokens,
                onCancel: { showTemplateSheet = false },
                onConfirm: confirmTemplateFeed
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ExportSettings.didChangeNotification)) { _ in
            exportDestinations = ExportSettings.loadDestinations()
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

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .foregroundStyle(LinearGradient.pastureBrand)
            Text("Pasture")
                .font(.pastureSheetHeading)
            Spacer()
            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
            .buttonStyle(.plain)
            .help("Open main window")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            TextField("Search\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(.caption))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - File List

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredFiles) { file in
                    MenuBarFileRow(
                        file: file,
                        isSelected: selectedFiles.contains(file),
                        colorScheme: colorScheme
                    ) {
                        if selectedFiles.contains(file) {
                            selectedFiles.remove(file)
                        } else {
                            selectedFiles.insert(file)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if !selectedFiles.isEmpty {
                Text("\(selectedFiles.count) selected")
                    .font(.pastureStatusBar)
                    .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            } else {
                Text("\(fm.files.count) files")
                    .font(.pastureStatusBar)
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }

            Spacer()

            feedButtonContent
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var feedButtonContent: some View {
        let isDisabled = selectedFiles.isEmpty

        if exportDestinations.isEmpty {
            Button(action: { executeFeed(destination: nil) }) {
                feedButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
        } else {
            Menu {
                Button("Copy to Clipboard") { executeFeed(destination: nil) }
                Divider()
                ForEach(exportDestinations) { dest in
                    Button("Export to \(dest.name)") { executeFeed(destination: dest) }
                }
            } label: {
                feedButtonLabel
            } primaryAction: {
                let defaultDest = resolveDefaultDestination()
                executeFeed(destination: defaultDest)
            }
            .menuStyle(.borderlessButton)
            .disabled(isDisabled)
        }
    }

    private var feedButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 10))
            Text("Feed \(TokenEstimator.formatted(totalTokens))")
                .font(.system(.caption, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            selectedFiles.isEmpty
                ? AnyShapeStyle(Color.pastureTextTertiaryLight.opacity(0.3))
                : AnyShapeStyle(LinearGradient.pastureFeedButton)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Feed Actions

    private func resolveDefaultDestination() -> ExportDestination? {
        guard let defaultID = ExportSettings.defaultDestinationID() else { return nil }
        return exportDestinations.first { $0.id == defaultID }
    }

    private func executeFeed(destination: ExportDestination?) {
        let targets = feedTargets
        guard !targets.isEmpty else { return }

        let allVars = TemplateEngine.extractVariables(from: targets.map(\.content).joined(separator: "\n"))
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
        let tokens = TokenEstimator.formatted(fm.totalTokens(for: targets))

        if let dest = destination {
            do {
                try fm.exportToFile(context, to: dest)
                withAnimation { feedbackMessage = "\(dest.name) \u{2190} \(label) \u{b7} ~\(tokens) tk" }
            } catch {
                withAnimation { feedbackMessage = "Export failed: \(error.localizedDescription)" }
            }
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(context, forType: .string)
            clipboardClearTrigger += 1
            withAnimation { feedbackMessage = "Copied \(label) \u{b7} ~\(tokens) tk" }
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let msg = feedbackMessage {
            Text(msg)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { feedbackMessage = nil }
                }
        }
    }
}
