import SwiftUI
import AppKit
import PastureKit

@MainActor
final class FeedService: ObservableObject {
    @Published var showTemplateSheet = false
    @Published var templateVariables: [TemplateVariable] = []
    @Published var feedbackMessage: String?

    private(set) var pendingFeedTargets: [MDFile] = []
    private(set) var pendingDestination: ExportDestination?
    private var clipboardClearTask: Task<Void, Never>?
    private var feedbackDismissTask: Task<Void, Never>?

    func executeFeed(targets: [MDFile], destination: ExportDestination?, fm: MDFileManager) {
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

        deliverFeed(context: fm.feedContext(files: targets), targets: targets, destination: destination, fm: fm)
    }

    func confirmTemplateFeed(fm: MDFileManager) {
        var rendered: [URL: String] = [:]
        for file in pendingFeedTargets {
            rendered[file.url] = TemplateEngine.render(file.content, with: templateVariables)
        }
        deliverFeed(
            context: fm.feedContext(files: pendingFeedTargets, renderedContents: rendered),
            targets: pendingFeedTargets,
            destination: pendingDestination,
            fm: fm
        )
        showTemplateSheet = false
        pendingFeedTargets = []
        templateVariables = []
        pendingDestination = nil
    }

    private func deliverFeed(context: String, targets: [MDFile], destination: ExportDestination?, fm: MDFileManager) {
        let label = targets.count == 1 ? targets[0].name : "\(targets.count) files"
        let tokenLabel = "~\(TokenEstimator.formatted(fm.totalTokens(for: targets))) tokens"

        if let dest = destination {
            do {
                try fm.exportToFile(context, to: dest)
                showFeedback("\(dest.name) \u{2190} \(label) \u{b7} \(tokenLabel)")
            } catch {
                showFeedback("Export failed: \(error.localizedDescription)")
            }
        } else {
            copyToClipboard(context, message: "Copied \(label) \u{b7} \(tokenLabel)")
        }
    }

    func copyToClipboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let savedCount = NSPasteboard.general.changeCount
        showFeedback(message)

        clipboardClearTask?.cancel()
        clipboardClearTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled,
                  NSPasteboard.general.changeCount == savedCount else { return }
            NSPasteboard.general.clearContents()
            showFeedback("Clipboard cleared")
        }
    }

    func showFeedback(_ message: String) {
        feedbackDismissTask?.cancel()
        withAnimation { feedbackMessage = message }
        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { feedbackMessage = nil }
        }
    }
}
