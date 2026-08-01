import Carbon.HIToolbox
import Foundation

extension Notification.Name {
    static let clipHavenOpenHistory = Notification.Name("ClipHaven.openHistory")
}

/// Registers the initial Command-Option-Space history shortcut with macOS.
final class GlobalShortcutController {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func start() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: .clipHavenOpenHistory, object: nil) }
            return noErr
        }, 1, &eventType, context, &eventHandler)
        let identifier = EventHotKeyID(signature: OSType(0x4348_564E), id: 1) // CHVN
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
