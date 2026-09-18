import Foundation

/// Decisión de "pegar desde el portapapeles", extraída de la vista para poder
/// vigilarla con tests.
///
/// El hotfix `3fb633e` movió la lectura del pasteboard al gesto del usuario
/// porque, con la privacidad de portapapeles de macOS 15.4+, un acceso
/// programático puede denegarse y devolver `nil` **en silencio**: el código
/// anterior hacía `?? ""` y creaba una nota en blanco sin ningún error. Ese
/// arreglo se quedó sin test (audit 360), y vivía entero en `ContentView`, donde
/// no se puede probar. La regla de decisión vive ahora aquí.
public enum ClipboardPaste {

    public enum Outcome: Equatable, Sendable {
        /// Hay texto utilizable: se abre la hoja de nombre con este contenido.
        case proceed(text: String)
        /// No se crea nada. `message` es lo que ve el usuario.
        case refuse(message: String)
    }

    public static let noTextMessage = "Clipboard has no text to paste"
    public static let blockedMessage = "macOS is blocking clipboard access — allow Pasture in System Settings → Privacy & Security → Paste from Other Apps"

    /// - Parameters:
    ///   - clipboardText: lo que devolvió el pasteboard; `nil` tanto si no hay
    ///     texto como si el sistema denegó el acceso sin avisar.
    ///   - accessDenied: si el sistema declara el acceso bloqueado, para poder
    ///     dar el mensaje accionable en vez del genérico.
    ///
    /// Invariante: **nunca** devuelve `.proceed` con contenido vacío. Es lo que
    /// impide la nota en blanco que motivó el hotfix.
    public static func outcome(clipboardText: String?, accessDenied: Bool) -> Outcome {
        guard let text = clipboardText, !text.isEmpty else {
            return .refuse(message: accessDenied ? blockedMessage : noTextMessage)
        }
        return .proceed(text: text)
    }
}
