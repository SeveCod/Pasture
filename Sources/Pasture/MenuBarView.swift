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
    @StateObject private var feedService = FeedService()

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
        .sheet(isPresented: $feedService.showTemplateSheet) {
            TemplateSheet(
                variables: $feedService.templateVariables,
                totalTokens: totalTokens,
                onCancel: { feedService.showTemplateSheet = false },
                onConfirm: { feedService.confirmTemplateFeed(fm: fm) }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ExportSettings.didChangeNotification)) { _ in
            exportDestinations = ExportSettings.loadDestinations()
        }
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
                .foregroundStyle(Color.pastureAccent)
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed \(TokenEstimator.formatted(totalTokens)) tokens")
    }

    // MARK: - Feed Actions

    private func resolveDefaultDestination() -> ExportDestination? {
        guard let defaultID = ExportSettings.defaultDestinationID() else { return nil }
        return exportDestinations.first { $0.id == defaultID }
    }

    private func executeFeed(destination: ExportDestination?) {
        feedService.executeFeed(targets: feedTargets, destination: destination, fm: fm)
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackOverlay: some View {
        if let msg = feedService.feedbackMessage {
            Text(msg)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
