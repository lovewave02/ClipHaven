import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private var changeCount = NSPasteboard.general.changeCount
    private weak var store: HistoryStore?
    private var timer: Timer?

    init(store: HistoryStore) { self.store = store }

    func start() {
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.inspectPasteboard() }
        }
        // The app is normally an accessory app, but temporarily switches run
        // loop modes while its history panel is key.  A default-mode-only timer
        // can then miss clipboard changes made in another app.  Common modes
        // keep capture continuous across those transitions.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func inspectPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmostApplication?.bundleIdentifier
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            store?.capture(.text(text), frontmostBundleID: bundleID)
        } else if let data = pasteboard.data(forType: .tiff), NSImage(data: data) != nil {
            store?.capture(.image(data), frontmostBundleID: bundleID)
        }
        if let frontmostApplication,
           frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            NotificationCenter.default.post(
                name: .clipHavenCapturedSource,
                object: NSNumber(value: frontmostApplication.processIdentifier)
            )
        }
    }
}
