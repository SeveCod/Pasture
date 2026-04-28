import SwiftUI

@main
struct PastureApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("File") {
                Button("Save") {
                    NotificationCenter.default.post(name: .forceSave, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Paste from Clipboard") {
                    NotificationCenter.default.post(name: .pasteFromClipboard, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}

extension Notification.Name {
    static let pasteFromClipboard = Notification.Name("pasteFromClipboard")
    static let forceSave = Notification.Name("forceSave")
}
