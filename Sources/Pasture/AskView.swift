import SwiftUI
import UniformTypeIdentifiers
import PastureKit

struct AskView: View {
    @ObservedObject var viewModel: AskViewModel
    let feedTargets: [MDFile]
    /// Shared with ContentView — toasts surface through its feedback overlay.
    @ObservedObject var feedService: FeedService
    @EnvironmentObject private var fm: MDFileManager
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("askPrivacyNoticeAccepted") private var privacyNoticeAccepted = false
    @State private var showPrivacyNotice = false

    private var contextTokens: Int { fm.totalTokens(for: feedTargets) }

    private var providerName: String {
        viewModel.resolvedModel.provider == .anthropic ? "Anthropic" : "OpenRouter"
    }

    /// Green below 50% of the model's context window, amber up to 80%, red above.
    private var contextUsageColor: Color {
        let window = viewModel.resolvedModel.contextWindow
        guard window > 0 else { return Color.pastureTokenBadgeText(colorScheme) }
        let ratio = Double(contextTokens) / Double(window)
        if ratio > 0.8 { return Color.pastureError(colorScheme) }
        if ratio > 0.5 { return Color.pastureWarning(colorScheme) }
        return Color.pastureTokenBadgeText(colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            contextBar
            Color.pastureDivider(colorScheme).frame(height: 1)
            responseArea
            Color.pastureDivider(colorScheme).frame(height: 1)
            inputBar
        }
        .background(Color.pastureEditor(colorScheme))
        .onReceive(NotificationCenter.default.publisher(for: AISettings.didChangeNotification)) { _ in
            viewModel.reloadSettings()
        }
        .alert("Send files to \(providerName)?", isPresented: $showPrivacyNotice) {
            Button("Send") {
                privacyNoticeAccepted = true
                performSend()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ask sends the full content of the selected files to \(providerName) to generate a response. This notice is shown only once.")
        }
    }

    // MARK: - Context Bar

    private var contextBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            Text("\(feedTargets.count) file\(feedTargets.count == 1 ? "" : "s")")
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            Text("\u{b7}")
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            Text("~\(TokenEstimator.formatted(contextTokens)) / \(TokenEstimator.formatted(viewModel.resolvedModel.contextWindow)) tokens")
                .font(.pastureTokenCount)
                .foregroundStyle(contextUsageColor)
                .help("Estimated context size vs. the model's context window")
                .accessibilityLabel("Approximately \(TokenEstimator.formatted(contextTokens)) of \(TokenEstimator.formatted(viewModel.resolvedModel.contextWindow)) tokens used")

            Spacer()

            if !viewModel.hasAPIKey {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.pastureError(colorScheme))
                        .accessibilityHidden(true)
                    Text("No API key")
                        .font(.pastureStatusBar)
                        .foregroundStyle(Color.pastureError(colorScheme))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: No API key configured")
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.system(size: 9))
                        .accessibilityHidden(true)
                    Text(viewModel.resolvedModel.displayName)
                }
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Color.pastureTokenBadgeBg(colorScheme),
                    in: RoundedRectangle(cornerRadius: PastureEffects.cornerRadiusSmall)
                )
                .help("Selected file contents are sent to \(providerName) when you ask")
                .accessibilityLabel("Model \(viewModel.resolvedModel.displayName). Selected file contents are sent to \(providerName) when you ask")

                Text(viewModel.costEstimate(for: contextTokens))
                    .font(.pastureTokenCount)
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
        }
        .padding(.horizontal, PastureLayout.statusBarHPadding)
        .padding(.vertical, PastureLayout.statusBarVPadding)
        .background(Color.pastureStatusBar(colorScheme))
    }

    // MARK: - Response Area

    @ViewBuilder
    private var responseArea: some View {
        if viewModel.responseText.isEmpty && !viewModel.isStreaming && viewModel.error == nil {
            askEmptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let error = viewModel.error {
                            errorView(error)
                        }

                        if !viewModel.responseText.isEmpty {
                            responseContent
                        }

                        if viewModel.isStreaming {
                            streamingIndicator
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(PastureLayout.askResponsePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.responseText) { _, _ in
                    withAnimation(.easeOut(duration: PastureEffects.animationQuick)) {
                        proxy.scrollTo("bottom")
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if !viewModel.responseText.isEmpty && !viewModel.isStreaming {
                Color.pastureDivider(colorScheme).frame(height: 1)
                actionBar
            }
        }
    }

    private var responseContent: some View {
        Group {
            if !viewModel.isStreaming,
               let attributed = try? AttributedString(
                   markdown: viewModel.responseText,
                   options: .init(interpretedSyntax: .full)
               ) {
                Text(attributed)
            } else {
                Text(viewModel.responseText)
            }
        }
        .textSelection(.enabled)
        .font(.body)
        .foregroundStyle(Color.pastureTextPrimary(colorScheme))
    }

    private var streamingIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.pastureAccent(colorScheme))
                .frame(width: 6, height: 6)
                .opacity(0.7)
                .modifier(PulseModifier(speed: PastureLayout.streamingPulseSpeed))
            Text("Generating\u{2026}")
                .font(.caption)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating response")
    }

    private func errorView(_ error: AIClientError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.pastureError(colorScheme))
                .accessibilityHidden(true)
            Text(error.localizedDescription)
                .font(.callout)
                .foregroundStyle(Color.pastureError(colorScheme))
        }
        .padding(12)
        .background(
            Color.pastureError(colorScheme).opacity(0.08),
            in: RoundedRectangle(cornerRadius: PastureEffects.cornerRadius)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(error.localizedDescription)")
    }

    private var askEmptyState: some View {
        VStack(spacing: PastureLayout.emptyStateSpacing) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: PastureLayout.emptyStateIconSize))
                .foregroundStyle(LinearGradient.pastureBrand)
                .padding(.bottom, 4)

            Text("Ask your context")
                .font(.pastureEmptyHeading)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))

            if feedTargets.isEmpty {
                Text("Select files in the sidebar, then ask a question")
                    .font(.pastureEmptySubtext)
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            } else {
                Text("Type a question below to ask about \(feedTargets.count) selected file\(feedTargets.count == 1 ? "" : "s")")
                    .font(.pastureEmptySubtext)
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Text("~\(TokenEstimator.formatted(TokenEstimator.estimate(viewModel.responseText))) tokens response")
                .font(.pastureTokenCount)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            Spacer()

            Button {
                viewModel.copyResponse()
                feedService.showFeedback("Copied to clipboard")
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.pastureStatusBar)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pastureAccent(colorScheme))
            .accessibilityLabel("Copy response")
            .accessibilityHint("Copies the AI response to the clipboard")

            Button {
                viewModel.saveResponse(to: fm, collection: feedTargets.first?.collection)
                feedService.showFeedback("Saved to Pasture")
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.pastureStatusBar)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pastureAccent(colorScheme))
            .accessibilityLabel("Save response to Pasture")
            .accessibilityHint("Saves the AI response as a new file in Pasture")

            Button {
                exportResponseToDisk()
            } label: {
                Label("Export .md", systemImage: "square.and.arrow.up")
                    .font(.pastureStatusBar)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.pastureAccent(colorScheme))
            .accessibilityLabel("Export response as Markdown")
            .accessibilityHint("Opens a save dialog to export the response as a Markdown file")
        }
        .padding(.horizontal, PastureLayout.statusBarHPadding)
        .frame(height: PastureLayout.askActionBarHeight)
        .background(Color.pastureStatusBar(colorScheme))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            if !viewModel.questionHistory.isEmpty {
                Menu {
                    ForEach(viewModel.questionHistory, id: \.self) { entry in
                        Button {
                            viewModel.question = entry
                        } label: {
                            Text(entry.count > 60 ? entry.prefix(60) + "\u{2026}" : entry)
                        }
                    }
                    Divider()
                    Button("Clear Recent Questions", role: .destructive) {
                        viewModel.clearQuestionHistory()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Recent questions")
                .accessibilityLabel("Recent questions")
            }

            TextField("Ask about your files\u{2026}", text: $viewModel.question, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...4)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: PastureEffects.cornerRadius)
                        .fill(Color.pastureStatusBar(colorScheme))
                )
                .onSubmit { sendIfReady() }

            if viewModel.isStreaming {
                Button(action: viewModel.stop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.pastureError(colorScheme))
                }
                .buttonStyle(.plain)
                .help("Stop generating")
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: sendIfReady) {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11))
                        Text("Ask")
                    }
                    .foregroundStyle(Color.pastureTextPrimaryLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.canSend && !feedTargets.isEmpty
                            ? AnyShapeStyle(LinearGradient.pastureFeedButton)
                            : AnyShapeStyle(Color.pastureTextTertiaryLight.opacity(0.3))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PastureLayout.feedButtonRadius))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend || feedTargets.isEmpty)
                .help(feedTargets.isEmpty ? "Select files first" : (viewModel.hasAPIKey ? "Send question" : "Configure API key in Settings"))
            }

            if !viewModel.responseText.isEmpty || viewModel.error != nil {
                Button(action: viewModel.clear) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
                .accessibilityLabel("Clear conversation")
            }
        }
        .padding(PastureLayout.askInputPadding)
    }

    // MARK: - Helpers

    private func sendIfReady() {
        guard viewModel.canSend, !feedTargets.isEmpty else { return }
        guard privacyNoticeAccepted else {
            showPrivacyNotice = true
            return
        }
        performSend()
    }

    private func performSend() {
        let context = fm.feedContext(files: feedTargets)
        viewModel.send(context: context, contextTokens: contextTokens)
    }

    private func exportResponseToDisk() {
        guard !viewModel.responseText.isEmpty else { return }
        let panel = NSSavePanel()
        let prefix = FilenameSanitizer.sanitize(String(viewModel.question.prefix(AskViewModel.responseFilenamePrefixLength)))
        panel.nameFieldStringValue = (prefix.isEmpty ? "response" : prefix) + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.message = "Export response as Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.responseText.write(to: url, atomically: true, encoding: .utf8)
            feedService.showFeedback("Exported to \(url.lastPathComponent)")
        } catch {
            feedService.showFeedback("Export failed: \(error.localizedDescription)", isError: true)
        }
    }
}

private struct PulseModifier: ViewModifier {
    let speed: Double
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 1.0 : 0.4)
            .animation(.easeInOut(duration: speed).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
