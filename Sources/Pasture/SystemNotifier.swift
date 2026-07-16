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
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
