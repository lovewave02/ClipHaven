import AppKit
import SwiftUI

@main
struct ClipHavenApp: App {
    @State private var store = HistoryStore()
    @State private var monitor: ClipboardMonitor?
    private let shortcut = GlobalShortcutController()

    init() { shortcut.start() }

    var body: some Scene {
        MenuBarExtra("ClipHaven", systemImage: "doc.on.clipboard") {
            HistoryPanel(store: store)
                .onAppear {
                    if monitor == nil {
                        let newMonitor = ClipboardMonitor(store: store)
                        newMonitor.start()
                        monitor = newMonitor
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("ClipHaven History", id: "history") {
            HistoryPanel(store: store)
        }

        Settings { SettingsView(store: store) }
    }
}

struct HistoryPanel: View {
    @Bindable var store: HistoryStore
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var confirmation: ClearChoice?
    @State private var notice: String?

    enum ClearChoice: String, Identifiable { case all, unpinned; var id: String { rawValue } }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("ClipHaven").font(.headline)
                Spacer()
                Toggle("Paused", isOn: $store.settings.isPaused).toggleStyle(.switch).labelsHidden()
            }
            TextField("Search history", text: $query).textFieldStyle(.roundedBorder)
            if let storageError = store.storageError {
                HStack { Text(storageError).font(.caption).foregroundStyle(.orange); Button("Retry", action: store.retryStorage) }
            }
            List(store.filteredItems(query: query)) { item in
                HStack(spacing: 10) {
                    if case let .image(data) = item.payload, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(.rect(cornerRadius: 5))
                    } else { Image(systemName: "text.alignleft").foregroundStyle(.secondary) }
                    VStack(alignment: .leading) {
                        Text(item.payload.preview).lineLimit(1)
                        Text(item.capturedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.togglePin(item.id) } label: { Image(systemName: item.isPinned ? "pin.fill" : "pin") }.buttonStyle(.plain)
                    Button(role: .destructive) { store.delete(item.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                }
                .contentShape(.rect)
                .onTapGesture { select(item) }
            }
            .frame(minHeight: 160)
            HStack {
                Button("Clear unpinned") { confirmation = .unpinned }
                Spacer()
                Button("Clear history", role: .destructive) { confirmation = .all }
            }
        }
        .padding(12).frame(width: 410, height: 480)
        .onReceive(NotificationCenter.default.publisher(for: .clipHavenOpenHistory)) { _ in
            openWindow(id: "history")
            NSApp.activate(ignoringOtherApps: true)
        }
        .alert("Clear history?", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            Button("Cancel", role: .cancel) { confirmation = nil }
            Button("Clear", role: .destructive) {
                if confirmation == .all { store.clearAll() } else { store.clearUnpinned() }
                confirmation = nil
            }
        } message: { Text(confirmation == .all ? "This permanently removes every retained item." : "This permanently removes unpinned items.") }
        .alert("ClipHaven", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) { Button("OK") { notice = nil } } message: { Text(notice ?? "") }
    }

    private func select(_ item: HistoryItem) {
        store.restore(item)
        guard store.settings.autoPaste else { notice = "Copied to clipboard. Paste it where you need it."; return }
        guard AXIsProcessTrusted() else { notice = "Copied to clipboard. Enable Accessibility in macOS Settings to use auto-paste."; return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

struct SettingsView: View {
    @Bindable var store: HistoryStore
    @State private var exclusion = ""

    var body: some View {
        Form {
            Section("History") {
                LabeledContent("Retention", value: "30 days")
                LabeledContent("Ordinary entries", value: "Up to 750")
                Toggle("Pause collection", isOn: $store.settings.isPaused)
            }
            Section("Reuse") { Toggle("Auto-paste (requires Accessibility)", isOn: $store.settings.autoPaste) }
            Section("Startup") { Toggle("Launch at login", isOn: $store.settings.launchAtLogin) }
            Section("Excluded applications") {
                HStack { TextField("Bundle identifier", text: $exclusion); Button("Add") { addExclusion() }.disabled(exclusion.isEmpty) }
                ForEach(store.settings.excludedBundleIDs.sorted(), id: \.self) { id in
                    HStack { Text(id); Spacer(); Button("Remove", role: .destructive) { store.settings.excludedBundleIDs.remove(id) } }
                }
            }
        }.padding().frame(width: 440)
    }

    private func addExclusion() { store.settings.excludedBundleIDs.insert(exclusion); exclusion = "" }
}
