import AppKit
import PastureKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated(unsafe) private var lockFD: Int32 = -1

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

        // v1.9 — integración de sistema: política de Dock + hotkeys globales.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if IntegrationSettings.hideDockIcon() {
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
                GlobalHotkeyManager.shared.start()
            }
        }
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
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(self)
            }
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}
