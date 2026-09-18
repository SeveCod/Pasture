import SwiftUI

@main
struct PastureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var fm = MDFileManager()
    /// El `FeedService` del popover lo posee la APP, no la vista.
    ///
    /// Como `@StateObject` de `MenuBarView` moría con el popover: al perder el
    /// foco —que es justo lo que pasa cuando aparece el aviso de secretos o la
    /// hoja de plantilla— la vista se destruía y con ella el `pendingSecretProceed`,
    /// así que el feed no se entregaba y nadie avisaba (audit 360, A5). Viviendo
    /// aquí, el estado pendiente sobrevive y el diálogo se repone al reabrir.
    @StateObject private var menuBarFeedService = FeedService()

    var body: some Scene {
        Window("Pasture", id: "main") {
            ContentView()
                .environmentObject(fm)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Grupo vacío a propósito: suprime el comando "New" por defecto de
            // SwiftUI. Borrar el CommandGroup entero lo repondría.
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

                Button("Refresh Sources") {
                    NotificationCenter.default.post(name: .refreshSources, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Toggle Ask Mode") {
                    NotificationCenter.default.post(name: .toggleAskMode, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Pasture", systemImage: "leaf.fill") {
            MenuBarView(feedService: menuBarFeedService)
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
    static let refreshSources = Notification.Name("refreshSources")
    static let performSearch = Notification.Name("performSearch")
}
