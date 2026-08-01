import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private var changeCount = NSPasteboard.general.changeCount
    private weak var store: HistoryStore?
    private var timer: Timer?

    init(store: HistoryStore) { self.store = store }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.inspectPasteboard() }
        }
    }

    private func inspectPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            store?.capture(.text(text), frontmostBundleID: bundleID)
        } else if let data = pasteboard.data(forType: .tiff), NSImage(data: data) != nil {
            store?.capture(.image(data), frontmostBundleID: bundleID)
        }
    }
}
