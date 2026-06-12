import SwiftUI
import AppKit
import PastureKit

struct MenuBarView: View {
    @EnvironmentObject private var fm: MDFileManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @State private var selectedFiles: Set<MDFile> = []
    @State private var searchText = ""
    @State private var exportDestinations: [ExportDestination] = ExportSettings.loadDestinations()
    @State private var presets: [SelectionPreset] = SelectionPresetStore.load()
    @StateObject private var feedService = FeedService()

    // Search is intentionally independent from the main window's, but the
    // predicate itself is shared (MDFile.matches) so both stay consistent.
    private var filteredFiles: [MDFile] {
        guard !searchText.isEmpty else { return fm.files }
        return fm.files.filter { $0.matches(query: searchText) }
    }

    private var feedTargets: [MDFile] {
        guard !selectedFiles.isEmpty else { return [] }
        return fm.files.filter { selectedFiles.contains($0) }
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
        .sheet(isPresented: $feedService.showTemplateSheet) {
            TemplateSheet(
                variables: $feedService.templateVariables,
                totalTokens: totalTokens,
                onCancel: { feedService.cancelTemplateFeed() },
                onConfirm: { feedService.confirmTemplateFeed(fm: fm) }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ExportSettings.didChangeNotification)) { _ in
            exportDestinations = ExportSettings.loadDestinations()
        }
        .onReceive(NotificationCenter.default.publisher(for: SelectionPresetStore.didChangeNotification)) { _ in
            presets = SelectionPresetStore.load()
        }
        .alert(
            "Possible secret detected",
            isPresented: Binding(
                get: { feedService.pendingSecretResult != nil },
                set: { if !$0 { feedService.cancelSecretDialog() } }
            ),
            presenting: feedService.pendingSecretResult
        ) { _ in
            Button("Cancel", role: .cancel) { feedService.cancelSecretDialog() }
            Button("Continue anyway", role: .destructive) { feedService.proceedDespiteSecrets() }
        } message: { result in
            Text(secretAlertMessage(for: result))
        }
    }

    /// Mensaje del aviso de secretos. SEC-4 (sin valores) + SEC-5 (best-effort).
    private func secretAlertMessage(for result: SecretScanResult) -> String {
        let detections = result.summaryLines().joined(separator: "\n")
        return """
        Pasture found patterns that look like known credentials:

        \(detections)

        This is a best-effort check for known secret types — it is not a guarantee. Review before sending.
        """
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .foregroundStyle(LinearGradient.pastureBrand)
                .accessibilityHidden(true)
            Text("Pasture")
                .font(.pastureSheetHeading)
            Spacer()

            if !presets.isEmpty {
                Menu {
                    ForEach(presets) { preset in
                        Button(preset.name) { applyPreset(preset) }
                    }
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.pastureAccent(colorScheme))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Apply a selection preset")
                .accessibilityLabel("Apply selection preset")
                .accessibilityHint("Opens a menu of saved presets")
            }

            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11))
                    Text("Open")
                        .font(.system(.caption, weight: .medium))
                }
                .foregroundStyle(Color.pastureAccent(colorScheme))
            }
            .buttonStyle(.plain)
            .help("Open main window")
            .accessibilityLabel("Open main window")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
            .buttonStyle(.plain)
            .help("Quit Pasture")
            .accessibilityLabel("Quit Pasture")
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
                .accessibilityLabel("Clear search")
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
        let targets = feedTargets
        return HStack {
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

            FeedButton(
                targets: targets,
                totalTokens: fm.totalTokens(for: targets),
                destinations: exportDestinations,
                compact: true,
                onClipboard: { executeFeed(destination: nil) },
                onExport: { dest in executeFeed(destination: dest) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Feed Actions

    private func executeFeed(destination: ExportDestination?) {
        feedService.executeFeed(targets: feedTargets, destination: destination, fm: fm)
    }

    /// Aplica un preset a la selección del menu bar (independiente de la ventana
    /// principal — contrato de v1.3). Toast accionable con los ausentes (M-3, HU-5/HU-6).
    private func applyPreset(_ preset: SelectionPreset) {
        let (files, missingPaths) = fm.resolve(preset)
        selectedFiles = Set(files)
        if let missing = SelectionPreset.missingFilesMessage(missingPaths: missingPaths) {
            feedService.showFeedback("Applied '\(preset.name)' — \(missing)")
        } else {
            feedService.showFeedback("Applied '\(preset.name)'")
        }
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let msg = feedService.feedbackMessage {
            FeedbackToast(message: msg, isError: feedService.feedbackIsError)
        }
    }
}
