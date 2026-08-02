import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

extension Notification.Name {
    static let clipHavenOpenHistory = Notification.Name("ClipHaven.openHistory")
    static let clipHavenConfirmSelection = Notification.Name("ClipHaven.confirmSelection")
    static let clipHavenCapturedSource = Notification.Name("ClipHaven.capturedSource")
}

enum GlobalShortcutConfiguration {
    static let keyCode = UInt32(kVK_Space)
    static let modifiers = UInt32(cmdKey | optionKey)
    static let identifier = EventHotKeyID(signature: OSType(0x4348_564E), id: 1) // CHVN
}

enum GlobalShortcutRegistration: Equatable {
    case eventTapAndHotKeyRegistered
    case registered
    case eventHandlerUnavailable(OSStatus)
    case shortcutUnavailable(OSStatus)

    var diagnostic: String {
        switch self {
        case .eventTapAndHotKeyRegistered:
            return "Command-Option-Space registered (HID event tap + Carbon fallback)"
        case .registered:
            return "Command-Option-Space registered (Carbon fallback; grant Input Monitoring for earliest consumption)"
        case let .eventHandlerUnavailable(status): return "Event handler unavailable (OSStatus \(status))"
        case let .shortcutUnavailable(status): return "Command-Option-Space unavailable (OSStatus \(status))"
        }
    }
}

/// Consumes the shortcut before the frontmost app receives it. The HID event
/// tap is global (unlike an in-app event monitor) and remains active while
/// ClipHaven is inactive. Carbon is registered at the same time as a fallback
/// for systems where Input Monitoring has not yet been granted.
final class GlobalShortcutController {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var globalMonitor: Any?

    @discardableResult
    func start() -> GlobalShortcutRegistration {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), Self.handleEvent, 1, &eventType, nil, &eventHandler)
        guard handlerStatus == noErr else { return .eventHandlerUnavailable(handlerStatus) }

        let shortcutStatus = RegisterEventHotKey(
            GlobalShortcutConfiguration.keyCode,
            GlobalShortcutConfiguration.modifiers,
            GlobalShortcutConfiguration.identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard shortcutStatus == noErr else { return .shortcutUnavailable(shortcutStatus) }

        // Do not treat creating a session-level tap as proof that it will see
        // keystrokes. It can sit behind a frontmost application. A HID tap is
        // installed after the Carbon fallback so either route can consume the
        // key without depending on ClipHaven being active.
        installGlobalMonitor()
        return installEventTap() ? .eventTapAndHotKeyRegistered : .registered
    }

    private func installEventTap() -> Bool {
        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: Self.handleGlobalKeyEvent,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapSource = source
        return true
    }

    /// A global AppKit monitor is deliberately a fallback, not the consuming
    /// mechanism: it receives key events while ClipHaven is inactive on macOS
    /// configurations where the event-tap callback is delayed or filtered.
    private func installGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            guard GlobalShortcutConfiguration.matches(keyCode: Int64(event.keyCode), flags: flags) else {
                return
            }
            Self.postOpenHistory(Self.capturedTargetPID())
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private static let handleEvent: EventHandlerUPP = { _, _, _ in
        postOpenHistory(capturedTargetPID())
        return noErr
    }

    private static let handleGlobalKeyEvent: CGEventTapCallBack = { _, type, event, userInfo in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                let controller = Unmanaged<GlobalShortcutController>.fromOpaque(userInfo).takeUnretainedValue()
                if let eventTap = controller.eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, GlobalShortcutConfiguration.matches(
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags
        ) else {
            return Unmanaged.passUnretained(event)
        }

        postOpenHistory(capturedTargetPID())
        return nil
    }

    /// Runs while the global key event is being consumed, before AppKit is
    /// asked to present ClipHaven's panel.
    private static func capturedTargetPID() -> NSNumber? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return NSNumber(value: application.processIdentifier)
    }

    private static func postOpenHistory(_ targetPID: NSNumber?) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipHavenOpenHistory, object: targetPID)
        }
    }
}

extension GlobalShortcutConfiguration {
    static func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let hasTargetModifiers = flags.contains(.maskCommand) && flags.contains(.maskAlternate)
        let hasExtraModifiers = flags.contains(.maskControl) || flags.contains(.maskShift)
        return keyCode == Int64(Self.keyCode) && hasTargetModifiers && !hasExtraModifiers
    }
}
