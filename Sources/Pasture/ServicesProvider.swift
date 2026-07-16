import AppKit

/// v1.9 — Proveedor del menú Servicios: "New Pasture Capture" sobre texto
/// seleccionado en cualquier app. El nombre del método DEBE coincidir con
/// NSMessage en Info.plist (capturePasture). Los servicios llegan por el
/// main run loop → el hop async + assumeIsolated es seguro.
final class ServicesProvider: NSObject {

    @objc func capturePasture(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text in selection" as NSString
            return
        }
        Task { @MainActor in
            HeadlessActions.capture(text: text)
        }
    }
}
