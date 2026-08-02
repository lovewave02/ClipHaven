import AppKit
import CoreGraphics

@MainActor
final class ClipHavenApplicationDelegate: NSObject, NSApplicationDelegate {
    let store = HistoryStore()
    private let statusBar = StatusBarController()
    private let shortcut = GlobalShortcutController()
    private var monitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchServices normally enforces this for an .app bundle, but a
        // direct executable launch (or a stale prior process) can bypass it.
        // Never create a second status item, event tap, or permission UI.
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "local.cliphaven.app"
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.processIdentifier != currentPID && $0.bundleIdentifier == bundleID
        }) {
            NSApp.terminate(nil)
            return
        }
        // A normal activation policy is required for the history window to own
        // key focus when ClipHaven is launched as an .app bundle.
        NSApp.setActivationPolicy(.regular)
        statusBar.install(store: store)

        let clipboardMonitor = ClipboardMonitor(store: store)
        clipboardMonitor.start()
        monitor = clipboardMonitor

        let registration = shortcut.start()
        statusBar.setShortcutRegistration(registration)

        if CommandLine.arguments.contains("--diagnose") {
            let message = "statusItem=\(statusBar.hasVisibleStatusItem) accessibilityTrusted=\(AXIsProcessTrusted()) eventPostingTrusted=\(CGPreflightPostEventAccess()) globalShortcut=\(registration.diagnostic)\n"
            FileHandle.standardOutput.write(Data(message.utf8))
            NSApp.terminate(nil)
        }
    }
}
