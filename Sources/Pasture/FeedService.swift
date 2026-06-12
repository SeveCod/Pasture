import SwiftUI
import AppKit
import PastureKit

@MainActor
final class FeedService: ObservableObject {
    @Published var showTemplateSheet = false
    @Published var templateVariables: [TemplateVariable] = []
    @Published var feedbackMessage: String?
    @Published var feedbackIsError = false

    /// F1 — Estado del diálogo de aviso de secretos. Cuando != nil, la vista
    /// presenta el aviso. El default seguro es Cancelar (SEC-6).
    @Published var pendingSecretResult: SecretScanResult?
    private var pendingSecretProceed: (@MainActor () -> Void)?

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

        // F1 — escaneo de secretos sobre el contenido (sin templates) antes de entregar.
        let inputs = scanInputs(for: targets, renderedContents: nil)
        guardSecrets(inputs: inputs) { [weak self] in
            guard let self else { return }
            self.deliverFeed(context: fm.feedContext(files: targets), targets: targets, destination: destination, fm: fm)
        }
    }

    func confirmTemplateFeed(fm: MDFileManager) {
        var rendered: [URL: String] = [:]
        for file in pendingFeedTargets {
            rendered[file.url] = TemplateEngine.render(file.content, with: templateVariables)
        }
        let targets = pendingFeedTargets
        let destination = pendingDestination
        // ADR-002: el escaneo va sobre el contenido RENDERIZADO (post-templates),
        // no el crudo con {{VARS}}. Un secreto inyectado por una variable se detecta.
        let inputs = scanInputs(for: targets, renderedContents: rendered)
        resetPendingFeed()
        guardSecrets(inputs: inputs) { [weak self] in
            guard let self else { return }
            self.deliverFeed(
                context: fm.feedContext(files: targets, renderedContents: rendered),
                targets: targets,
                destination: destination,
                fm: fm
            )
        }
    }

    // MARK: — F1: escaneo de secretos (SEC-1, SEC-6)

    /// Construye los inputs del escáner a partir de la selección y, opcionalmente,
    /// el contenido renderizado (ADR-002: se escanea lo que de verdad sale).
    func scanInputs(for targets: [MDFile], renderedContents: [URL: String]?) -> [SecretScanner.Input] {
        targets.map { file in
            SecretScanner.Input(
                fileName: file.name,
                content: renderedContents?[file.url] ?? file.content
            )
        }
    }

    /// Escanea OFF the main actor; si hay coincidencias presenta el diálogo
    /// (default Cancelar), si no, ejecuta la continuación directamente.
    /// Cero fricción en el caso limpio (HU-1).
    func guardSecrets(inputs: [SecretScanner.Input], onProceed: @escaping @MainActor () -> Void) {
        // I-2: invariante de no-reentrada. Si ya hay un diálogo de secretos pendiente
        // de decisión del usuario, ignoramos el nuevo feed para no sobrescribir la
        // continuación en vuelo (que perdería el feed original y entregaría el nuevo
        // bajo la decisión del primer diálogo). El usuario resuelve el aviso actual primero.
        guard pendingSecretResult == nil else {
            showFeedback("Resolve the current secret warning first")
            return
        }
        Task {
            // SecretScanner.scan es nonisolated y Sendable-safe -> corre off-main (SEC-3).
            let result = await Task.detached(priority: .userInitiated) {
                SecretScanner.scan(inputs)
            }.value

            // Re-chequeo tras el hop async: otro feed pudo abrir un diálogo mientras
            // escaneábamos. No pisamos un diálogo ya presentado.
            guard pendingSecretResult == nil else {
                showFeedback("Resolve the current secret warning first")
                return
            }

            if result.isEmpty {
                onProceed()
            } else {
                pendingSecretProceed = onProceed
                pendingSecretResult = result
            }
        }
    }

    /// "Enviar de todas formas": continúa con el contenido ORIGINAL (sin redactar).
    /// El override es efímero, no se persiste (SEC-6).
    func proceedDespiteSecrets() {
        let proceed = pendingSecretProceed
        dismissSecretDialog()
        proceed?()
    }

    /// Cancelar / Escape: no se entrega nada (default seguro, SEC-6).
    func cancelSecretDialog() {
        dismissSecretDialog()
    }

    private func dismissSecretDialog() {
        pendingSecretResult = nil
        pendingSecretProceed = nil
    }

    func cancelTemplateFeed() {
        resetPendingFeed()
    }

    private func resetPendingFeed() {
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
                showFeedback("Export failed: \(error.localizedDescription)", isError: true)
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

    func showFeedback(_ message: String, isError: Bool = false) {
        feedbackDismissTask?.cancel()
        feedbackIsError = isError
        withAnimation { feedbackMessage = message }
        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(PastureLayout.toastDismissDelay))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { feedbackMessage = nil }
        }
    }
}
