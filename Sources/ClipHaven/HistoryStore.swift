import AppKit
import Foundation
import Observation

struct ClipSettings: Codable, Sendable {
    static let retentionDays = 30
    static let ordinaryLimit = 750
    var isPaused = false
    var autoPaste = false
    var excludedBundleIDs: Set<String> = []
}

@MainActor @Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    var settings = ClipSettings()
    private(set) var storageError: String?
    private let persistence: HistoryPersistence

    init(persistence: HistoryPersistence = .default) {
        self.persistence = persistence
        load()
    }

    func filteredItems(query: String) -> [HistoryItem] {
        let normalized = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matching = normalized.isEmpty ? items : items.filter { item in
            guard case let .text(value) = item.payload else { return false }
            return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized)
        }
        return matching.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.capturedAt > rhs.capturedAt
        }
    }

    func capture(_ payload: ClipPayload, frontmostBundleID: String? = nil, now: Date = .now) {
        guard !settings.isPaused, frontmostBundleID.map({ !settings.excludedBundleIDs.contains($0) }) ?? true else { return }
        if let newest = items.first, newest.payload == payload {
            items[0].capturedAt = now
        } else {
            items.insert(HistoryItem(payload: payload, capturedAt: now, sourceBundleIdentifier: frontmostBundleID), at: 0)
        }
        sweepRetention(now: now)
        trimOrdinaryEntries()
        save()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    func setPaused(_ isPaused: Bool) {
        settings.isPaused = isPaused
        save()
    }

    func setAutoPaste(_ enabled: Bool) {
        settings.autoPaste = enabled
        save()
    }

    func delete(_ id: UUID) { items.removeAll { $0.id == id }; save() }
    func clearAll() { items.removeAll(); save() }
    func clearUnpinned() { items.removeAll { !$0.isPinned }; save() }

    func sweepRetention(now: Date = .now) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -ClipSettings.retentionDays, to: now) ?? now
        items.removeAll { !$0.isPinned && $0.capturedAt < cutoff }
    }

    func restore(_ item: HistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.payload {
        case let .text(value): pasteboard.setString(value, forType: .string)
        case let .image(data):
            guard let image = NSImage(data: data) else { return }
            pasteboard.writeObjects([image])
        }
    }

    func retryStorage() { save() }

    private func trimOrdinaryEntries() {
        let ordinaryIndices = items.indices.filter { !items[$0].isPinned }
        guard ordinaryIndices.count > ClipSettings.ordinaryLimit else { return }
        for index in ordinaryIndices.dropFirst(ClipSettings.ordinaryLimit).sorted(by: >) { items.remove(at: index) }
    }

    private func load() {
        do {
            let snapshot = try persistence.load()
            items = snapshot.items; settings = snapshot.settings; sweepRetention()
        } catch HistoryPersistence.Error.noSavedData {
            return
        } catch {
            storageError = "History storage is unavailable. Existing items are read-only."
        }
    }

    private func save() {
        do { try persistence.save(.init(items: items, settings: settings)); storageError = nil }
        catch { storageError = "History storage is unavailable. Existing items are read-only." }
    }
}

struct HistorySnapshot: Codable, Sendable { var items: [HistoryItem]; var settings: ClipSettings }

struct HistoryPersistence: Sendable {
    enum Error: Swift.Error { case noSavedData }
    let url: URL
    static let `default` = HistoryPersistence(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipHaven", isDirectory: true).appendingPathComponent("history.json"))

    func load() throws -> HistorySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Error.noSavedData }
        return try JSONDecoder().decode(HistorySnapshot.self, from: Data(contentsOf: url))
    }

    func save(_ snapshot: HistorySnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
