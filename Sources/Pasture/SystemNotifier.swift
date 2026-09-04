import AppKit
import Foundation
import UserNotifications

/// v1.9 — Feedback de acciones headless vía Centro de Notificaciones.
/// Gotcha: UNUserNotificationCenter exige un bundle real (.app). Bajo
/// `swift run` (ejecutable suelto) el bundle proxy es nil y el framework
/// aborta: en ese caso degradamos a stderr y seguimos.
@MainActor
enum SystemNotifier {

    private static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func notify(title: String, body: String) {
        guard isBundled else {
            FileHandle.standardError.write(Data("[Pasture] \(title): \(body)\n".utf8))
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                // Sin permiso, el aviso moriría en silencio: al menos un beep y stderr,
                // que para "feed cancelled by secret" es la diferencia entre saberlo y no.
                DispatchQueue.main.async { NSSound.beep() }
                FileHandle.standardError.write(Data("[Pasture] (notifications denied) \(title): \(body)\n".utf8))
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            // El centro se pide dentro de la closure: capturarlo la haría retener un
            // UNUserNotificationCenter (no Sendable) en un contexto @Sendable.
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// Pide el permiso de notificaciones en el momento en que el usuario activa los
    /// hotkeys, no en el primer disparo (donde el diálogo del sistema sorprende).
    static func ensurePermission() async {
        guard isBundled else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// `true` solo si el usuario denegó explícitamente: `.notDetermined` aún puede
    /// concederse y no justifica avisar de nada.
    static func isDenied() async -> Bool {
        guard isBundled else { return false }
        return await authorizationStatus() == .denied
    }

    /// Solo el estado (Sendable) cruza actores: `UNNotificationSettings` no lo es y
    /// el compilador de CI (más nuevo que el local) rechaza que salga del closure.
    private nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}
