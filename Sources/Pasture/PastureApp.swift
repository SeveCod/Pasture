import SwiftUI

@main
struct PastureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var fm = MDFileManager()

    var body: some Scene {
        Window("Pasture", id: "main") {
            ContentView()
                .environmentObject(fm)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("File") {
                Button("Open in Default Editor") {
                    NotificationCenter.default.post(name: .openInEditor, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Paste from Clipboard") {
                    NotificationCenter.default.post(name: .pasteFromClipboard, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Divider()

                Button("Sync All Packs") {
                    NotificationCenter.default.post(name: .syncAllPacks, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Toggle Ask Mode") {
                    NotificationCenter.default.post(name: .toggleAskMode, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Pasture", systemImage: "leaf.fill") {
            MenuBarView()
                .environmentObject(fm)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let pasteFromClipboard = Notification.Name("pasteFromClipboard")
    static let openInEditor = Notification.Name("openInEditor")
    static let toggleAskMode = Notification.Name("toggleAskMode")
    static let syncAllPacks = Notification.Name("syncAllPacks")
}
