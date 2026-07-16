import AppKit
import PastureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) private var lockFD: Int32 = -1
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let lockPath = NSTemporaryDirectory() + "com.sevecod.pasture.lock"
        lockFD = Darwin.open(lockPath, O_WRONLY | O_CREAT, 0o600)
        guard lockFD >= 0 else { return }

        if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            Darwin.close(lockFD)
            lockFD = -1
            let myPID = ProcessInfo.processInfo.processIdentifier
            if let existing = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.sevecod.pasture" && $0.processIdentifier != myPID
            }) {
                existing.activate()
            }
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return
        }

        // v1.9 — integración de sistema: política de Dock, hotkeys globales
        // y menú Servicios.
        let provider = servicesProvider
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if IntegrationSettings.hideDockIcon() {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
                GlobalHotkeyManager.shared.start()
                NSApplication.shared.servicesProvider = provider
                NSUpdateDynamicServices()
            }
        }
    }

    /// v1.9 — dispatch del URL scheme `pasture://` (parser puro en PastureKit).
    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for url in urls {
                    guard let command = PastureURLCommand.parse(url) else { continue }
                    switch command {
                    case .feed(let presetName):
                        if let presetName {
                            HeadlessActions.feed(named: presetName)
                        } else {
                            HeadlessActions.feedDefaultPreset()
                        }
                    case .new(let title, let text):
                        HeadlessActions.capture(text: text ?? "", title: title)
                    case .search(let query):
                        self.showMainWindow()
                        NotificationCenter.default.post(name: .performSearch, object: query)
                    }
                }
            }
        }
    }

    @MainActor
    func showMainWindow() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(self)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if lockFD >= 0 {
            Darwin.close(lockFD)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }
}
