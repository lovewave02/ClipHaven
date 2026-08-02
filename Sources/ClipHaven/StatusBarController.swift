import AppKit
import CoreGraphics
import OSLog

/// Owns every interactive surface used to choose and paste a history item.
/// Keeping this in AppKit is intentional: neither table activation nor Return
/// depends on SwiftUI focus propagation.
@MainActor
final class StatusBarController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private static let pasteLogger = Logger(subsystem: "local.cliphaven.app", category: "AutoPaste")
    private var statusItem: NSStatusItem?
    private var historyWindow: NSWindow?
    private var tableView: HistoryTableView?
    private var autoPasteCheckbox: NSButton?
    private var pauseCheckbox: NSButton?
    private var store: HistoryStore?
    private var displayedItems: [HistoryItem] = []
    private var pasteTargetApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?
    private var observer: NSObjectProtocol?
    private var captureObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var visibilityRetry: Timer?
    private var isRestoringAndPasting = false
    private var lastGlobalOpenRequest = Date.distantPast

    private(set) var shortcutRegistration: GlobalShortcutRegistration = .shortcutUnavailable(-1) {
        didSet { statusItem?.button?.toolTip = "ClipHaven — \(shortcutRegistration.diagnostic)" }
    }

    func install(store: HistoryStore) {
        self.store = store
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = Bundle.main.url(forResource: "ClipHavenIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipHaven history")
        image?.size = NSSize(width: 18, height: 18)
        item.button?.image = image
        item.button?.title = " ClipHaven"
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggleHistory)
        item.button?.toolTip = "ClipHaven"
        item.isVisible = true
        statusItem = item

        visibilityRetry = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(reassertStatusItemVisibility), userInfo: nil, repeats: false)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            Task { @MainActor in self?.lastExternalApplication = application }
        }
        observer = NotificationCenter.default.addObserver(forName: .clipHavenOpenHistory, object: nil, queue: .main) { [weak self] notification in
            let targetPID = (notification.object as? NSNumber).map { pid_t($0.int32Value) }
            Task { @MainActor in self?.handleGlobalOpenRequest(targetPID: targetPID) }
        }
        captureObserver = NotificationCenter.default.addObserver(forName: .clipHavenCapturedSource, object: nil, queue: .main) { [weak self] notification in
            guard let pid = (notification.object as? NSNumber).map({ pid_t($0.int32Value) }),
                  let application = NSRunningApplication(processIdentifier: pid) else { return }
            Task { @MainActor in
                self?.lastExternalApplication = application
                self?.pasteTargetApplication = application
            }
        }
    }

    func setShortcutRegistration(_ registration: GlobalShortcutRegistration) { shortcutRegistration = registration }

    private func handleGlobalOpenRequest(targetPID: pid_t?) {
        // HID, Carbon, and AppKit monitoring are layered registration paths.
        // A consumed keystroke can reach more than one, but it must produce one
        // panel presentation and one saved destination.
        let now = Date.now
        // Carbon, HID tap, and AppKit may deliver the one physical shortcut on
        // separate run-loop turns. Keep the original target and panel stable
        // until that fan-out has drained.
        guard now.timeIntervalSince(lastGlobalOpenRequest) > 2.0 else { return }
        lastGlobalOpenRequest = now
        showHistory(targetPID: targetPID)
    }

    @objc private func toggleHistory() {
        if historyWindow?.isVisible == true {
            dismissHistory()
        } else {
            showHistory()
        }
    }

    @objc private func reassertStatusItemVisibility() { statusItem?.isVisible = true }

    /// Must run before AppKit activates ClipHaven, otherwise the target would
    /// incorrectly become our own process.
    func showHistory(targetPID: pid_t? = nil) {
        // A global-hotkey callback can activate ClipHaven before this main-actor
        // method runs. Prefer its synchronously captured PID so the destination
        // is always the app that was active before our UI appeared.
        let frontmost = targetPID.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            pasteTargetApplication = frontmost
        }
        NSApp.setActivationPolicy(.regular)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        showHistoryWindow()
    }

    private func showHistoryWindow() {
        guard store != nil else { return }
        refreshDisplayedItems()

        let window: NSWindow
        if let historyWindow {
            window = historyWindow
        } else {
            let panel = HistoryWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 510), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            panel.title = "ClipHaven History"
            panel.isReleasedWhenClosed = false
            panel.onConfirmSelection = { [weak self] in self?.activateSelectedRow(nil) }
            panel.contentViewController = makePanelController()
            historyWindow = panel
            window = panel
        }
        tableView?.reloadData()
        if !displayedItems.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tableView)
    }

    private func makePanelController() -> NSViewController {
        let controller = NSViewController()
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "ClipHaven")
        title.font = .preferredFont(forTextStyle: .headline)
        let hint = NSTextField(labelWithString: "Select an item, then press Return to paste")
        hint.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        let table = HistoryTableView()
        table.headerView = nil
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 44
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(activateSelectedRow(_:))
        table.onActivate = { [weak self] in self?.activateSelectedRow(nil) }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history"))
        column.width = 400
        table.addTableColumn(column)
        scrollView.documentView = table
        tableView = table

        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let pause = NSButton(checkboxWithTitle: "Pause collection", target: self, action: #selector(togglePauseCollection(_:)))
        pause.state = (store?.settings.isPaused ?? false) ? .on : .off
        pauseCheckbox = pause
        let autoPaste = NSButton(checkboxWithTitle: "Auto-paste (Accessibility required)", target: self, action: #selector(toggleAutoPaste(_:)))
        autoPaste.state = (store?.settings.autoPaste ?? false) ? .on : .off
        autoPasteCheckbox = autoPaste
        let paste = NSButton(title: "Paste selected", target: self, action: #selector(activateSelectedRow(_:)))
        // AppKit's key-equivalent resolver is the final responder fallback for
        // Return, including when an accessibility client owns table focus.
        paste.keyEquivalent = "\r"
        let clear = NSButton(title: "Clear history", target: self, action: #selector(clearHistory(_:)))
        let buttons = NSStackView(views: [quit, pause, autoPaste, NSView(), paste, clear])
        buttons.orientation = .horizontal
        buttons.distribution = .fill

        let stack = NSStackView(views: [title, hint, scrollView, buttons])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
        controller.view = root
        return controller
    }

    @objc fileprivate func activateSelectedRow(_ sender: Any?) {
        guard let tableView else { return }
        // AX clients can mark a row selected before AppKit updates
        // `selectedRow`. The panel always preselects its most-recent row, so
        // retaining that deterministic fallback preserves the same item for
        // Return instead of dropping the user's activation.
        let row = displayedItems.indices.contains(tableView.selectedRow)
            ? tableView.selectedRow
            : displayedItems.indices.first
        guard let row else { return }
        restoreAndPaste(itemID: displayedItems[row].id)
    }

    /// The sole activation operation. AppKit row double-click and both Return
    /// key variants feed this exact method via `HistoryTableView`.
    func restoreAndPaste(itemID: UUID) {
        guard !isRestoringAndPasting,
              let store,
              let item = store.items.first(where: { $0.id == itemID }) else { return }
        let destination = pasteTargetApplication
            ?? item.sourceBundleIdentifier.flatMap { identifier in
                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == identifier }
            }
            ?? lastExternalApplication
        guard let destination,
              destination.processIdentifier != NSRunningApplication.current.processIdentifier else {
            reportHold("HOLD: No destination application was captured before ClipHaven opened.")
            return
        }

        isRestoringAndPasting = true
        store.restore(item)
        guard store.settings.autoPaste else {
            dismissHistory()
            return
        }
        guard accessibilityIsTrustedOrRequestIt() else {
            reportHold("Auto-paste needs Accessibility permission. System Settings was opened.")
            isRestoringAndPasting = false
            return
        }
        dismissHistory()
        // A history-window click has made ClipHaven active. Request the
        // destination's windows explicitly before the bounded paste wait.
        destination.activate(options: [.activateAllWindows])
        waitForWorkspaceActivation(of: destination, payload: item.payload, attemptsRemaining: 20)
    }

    private func dismissHistory() {
        historyWindow?.orderOut(nil)
    }

    /// A bounded activation wait prevents a Cmd-V event from being sent to the
    /// disappearing panel. Exactly one HID paste is emitted on success.
    private func waitForWorkspaceActivation(of destination: NSRunningApplication, payload: ClipPayload, attemptsRemaining: Int) {
        guard isRestoringAndPasting else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.isRestoringAndPasting else { return }
                self.postSingleCommandVPaste(into: destination, payload: payload)
                self.isRestoringAndPasting = false
            }
        } else if attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.waitForWorkspaceActivation(of: destination, payload: payload, attemptsRemaining: attemptsRemaining - 1)
            }
        } else {
            isRestoringAndPasting = false
            reportHold("HOLD: The destination application did not become active before paste timed out.")
        }
    }

    private func postSingleCommandVPaste(into destination: NSRunningApplication, payload: ClipPayload) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Some unsigned local bundles can restore and activate the target but
        // have their HID event discarded despite an already-granted UI
        // permission. For text, use the same Accessibility permission to
        // insert at the focused target as a deterministic fallback.
        guard case let .text(text) = payload else { return }
        // A frontmost-app transition completes before its text editor always
        // regains keyboard focus. Leave one bounded settling interval so the
        // focused AX element belongs to the destination document, then only
        // fall back if the HID paste has not already appeared.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            Self.insertTextFallback(text, into: destination)
        }
    }

    private static func insertTextFallback(_ text: String, into destination: NSRunningApplication) {
        let application = AXUIElementCreateApplication(destination.processIdentifier)
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusedResult == .success, let focusedValue else {
            pasteLogger.error("AX focused-element lookup failed: \(focusedResult.rawValue, privacy: .public)")
            return
        }
        let focused = focusedValue as! AXUIElement
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &value) == .success,
           let value = value as? String,
           value.contains(text) {
            pasteLogger.debug("HID paste completed before AX fallback")
            return
        }
        let insertResult = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        pasteLogger.notice("AX selected-text insertion result: \(insertResult.rawValue, privacy: .public)")

        // TextEdit accepts AXSelectedText on some macOS releases but silently
        // leaves the visible editor unchanged on others. Verify once, then
        // replace only the current selection through AXValue. This remains an
        // Accessibility operation (not synthetic input), so it works without
        // asking for Input Monitoring and never writes outside the focused
        // editable element.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.replaceSelectionValueIfNeeded(text, in: focused)
        }
    }

    private static func replaceSelectionValueIfNeeded(_ text: String, in focused: AXUIElement) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &value) == .success,
              let current = value as? String,
              !current.contains(text) else { return }

        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
              let selectedRangeValue else {
            pasteLogger.error("AX selected-text range is unavailable for value fallback")
            return
        }
        let axRange = selectedRangeValue as! AXValue
        guard
              AXValueGetType(axRange) == .cfRange else {
            pasteLogger.error("AX selected-text range is unavailable for value fallback")
            return
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &selectedRange),
              let replacementRange = Range(NSRange(location: selectedRange.location, length: selectedRange.length), in: current) else {
            pasteLogger.error("AX selected-text range could not be applied to value")
            return
        }

        let replacement = current.replacingCharacters(in: replacementRange, with: text)
        let result = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, replacement as CFTypeRef)
        pasteLogger.notice("AX value fallback result: \(result.rawValue, privacy: .public)")
    }

    private func reportHold(_ message: String) {
        statusItem?.button?.toolTip = "ClipHaven — \(message)"
        NSSound.beep()
    }

    private func accessibilityIsTrustedOrRequestIt() -> Bool {
        guard !AXIsProcessTrusted() else { return true }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        return false
    }


    @objc private func clearHistory(_ sender: Any?) {
        store?.clearAll()
        refreshDisplayedItems()
        tableView?.reloadData()
    }

    @objc private func togglePauseCollection(_ sender: NSButton) {
        store?.setPaused(sender.state == .on)
        pauseCheckbox?.state = sender.state
    }

    @objc private func toggleAutoPaste(_ sender: NSButton) {
        store?.setAutoPaste(sender.state == .on)
        autoPasteCheckbox?.state = sender.state
        if sender.state == .on, !accessibilityIsTrustedOrRequestIt() {
            reportHold("Auto-paste needs Accessibility permission. System Settings was opened.")
        }
    }

    private func refreshDisplayedItems() {
        displayedItems = store?.filteredItems(query: "") ?? []
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedItems.count else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("HistoryRow")
        let view = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        view.textField?.stringValue = displayedItems[row].payload.preview
        return view
    }

    var hasVisibleStatusItem: Bool { statusItem?.isVisible == true && statusItem?.button != nil }

}

/// NSTableView owns the keyboard responder path. It treats Return and keypad
/// Enter equivalently and never relies on a SwiftUI List's focus state.
@MainActor
private final class HistoryTableView: NSTableView {
    var onActivate: (() -> Void)?
    /// A primary row press is an AppKit-owned activation path.  It deliberately
    /// resolves through the same controller operation as Return, rather than a
    /// SwiftUI gesture or a second paste implementation.
    override func mouseUp(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        super.mouseUp(with: event)
        guard row >= 0 else { return }
        onActivate?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }
        guard selectedRow >= 0 else { return }
        onActivate?()
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.insertNewline(_:)) ||
            selector == #selector(NSResponder.insertLineBreak(_:)) {
            onActivate?()
            return
        }
        super.doCommand(by: selector)
    }
}

/// Accessibility-driven selection can make the window, instead of the table,
/// the first responder.  Owning Return at the AppKit window boundary keeps the
/// keyboard contract deterministic while still routing through the same
/// controller operation as a row press.
@MainActor
private final class HistoryWindow: NSWindow {
    var onConfirmSelection: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 36 || event.keyCode == 76 {
            onConfirmSelection?()
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36 || event.keyCode == 76 {
            onConfirmSelection?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
