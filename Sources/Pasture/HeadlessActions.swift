import AppKit
import PastureKit

/// v1.9 — Acciones sin ventana: feed del preset por defecto al portapapeles
/// y captura rápida (hotkey global, menú Servicios, pasture://). La lógica
/// con decisiones vive en PastureKit (HeadlessFeed/QuickCapture); aquí solo
/// el pegamento AppKit: pasteboard, disco, notificación.
@MainActor
enum HeadlessActions {

    // MARK: - Feed

    /// Feed del preset por defecto. Sin default configurado: si existe
    /// exactamente un preset se usa ese; si no, se pide configuración.
    static func feedDefaultPreset() {
        let presets = SelectionPresetStore.load()
        let preset: SelectionPreset?
        if let id = IntegrationSettings.defaultPresetID() {
            preset = presets.first(where: { $0.id == id })
        } else if presets.count == 1 {
            preset = presets.first
        } else {
            preset = nil
        }
        guard let preset else {
            SystemNotifier.notify(
                title: "Pasture",
                body: "No default preset configured. Pick one in Settings → General."
            )
            return
        }
        feed(preset: preset)
    }

    static func feed(named name: String) {
        guard let preset = SelectionPresetStore.preset(named: name) else {
            SystemNotifier.notify(title: "Pasture", body: "Preset '\(name)' not found.")
            return
        }
        feed(preset: preset)
    }

    private static func feed(preset: SelectionPreset) {
        let outcome = HeadlessFeed.build(
            preset: preset,
            base: MDFileManager.pastureDir,
            format: FeedFormatSettings.feedFormat()
        )
        switch outcome {
        case .success(let result):
            copyWithAutoClear(result.context)
            var body = "'\(preset.name)': \(result.fileCount) files, \(TokenEstimator.formatted(result.tokens)) tokens copied."
            if !result.missingPaths.isEmpty {
                body += " Missing: \(result.missingPaths.joined(separator: ", "))."
            }
            SystemNotifier.notify(title: "Context copied", body: body)
        case .noFiles:
            SystemNotifier.notify(
                title: "Feed cancelled",
                body: "No files from '\(preset.name)' exist on disk."
            )
        case .secretsDetected(let lines):
            SystemNotifier.notify(
                title: "Possible secret detected — feed cancelled",
                body: lines.joined(separator: "\n") + "\nReview and feed from the app."
            )
        }
    }

    /// Copia preservando el invariante de seguridad del feed GUI:
    /// auto-clear a los 60 s si el usuario no ha copiado otra cosa.
    private static func copyWithAutoClear(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }

    // MARK: - Capture

    /// Captura texto a una nota nueva en `Captures/`. El DirectoryWatcher
    /// del manager recoge el fichero nuevo solo (0,5 s de debounce).
    @discardableResult
    static func capture(text: String, title: String? = nil) -> String? {
        guard let proposal = QuickCapture.proposal(text: text, title: title) else {
            SystemNotifier.notify(title: "Nothing to capture", body: "No text available.")
            return nil
        }
        let dir = MDFileManager.pastureDir
            .appendingPathComponent(QuickCapture.collectionName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = FileLibrary.deduplicatedURL(baseName: proposal.baseName, ext: "md", in: dir)
            try proposal.content.write(to: url, atomically: true, encoding: .utf8)
            SystemNotifier.notify(
                title: "Captured",
                body: "\(url.lastPathComponent) → \(QuickCapture.collectionName)/"
            )
            return url.lastPathComponent
        } catch {
            SystemNotifier.notify(title: "Capture failed", body: error.localizedDescription)
            return nil
        }
    }

    static func captureClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        capture(text: text)
    }
}
