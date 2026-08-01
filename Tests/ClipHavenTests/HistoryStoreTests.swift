import Foundation
import Testing
@testable import ClipHaven

@MainActor
struct HistoryStoreTests {
    private func store() -> HistoryStore {
        HistoryStore(persistence: HistoryPersistence(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    @Test func adjacentDuplicateRefreshesInsteadOfAppending() {
        let history = store()
        let first = Date(timeIntervalSince1970: 100)
        history.capture(.text("same"), now: first)
        history.capture(.text("same"), now: first.addingTimeInterval(5))
        #expect(history.items.count == 1)
        #expect(history.items[0].capturedAt == first.addingTimeInterval(5))
    }

    @Test func searchIsCaseAndDiacriticInsensitiveAndExcludesImages() {
        let history = store()
        history.capture(.text("Café Morning"))
        history.capture(.image(Data([0x01])))
        #expect(history.filteredItems(query: "CAFE").count == 1)
        #expect(history.filteredItems(query: "").count == 2)
    }

    @Test func retentionKeepsPinnedItems() {
        let history = store()
        let old = Date.now.addingTimeInterval(-31 * 86_400)
        history.capture(.text("ordinary"), now: old)
        history.capture(.text("pinned"), now: old)
        history.togglePin(history.items[0].id)
        history.sweepRetention(now: .now)
        #expect(history.items.count == 1)
        #expect(history.items[0].isPinned)
    }

    @Test func pauseAndExclusionsPreventCapture() {
        let history = store()
        history.settings.isPaused = true
        history.capture(.text("paused"))
        history.settings.isPaused = false
        history.settings.excludedBundleIDs = ["example.blocked"]
        history.capture(.text("excluded"), frontmostBundleID: "example.blocked")
        #expect(history.items.isEmpty)
    }

    @Test func clearUnpinnedLeavesPinnedAndClearAllRemovesEverything() {
        let history = store()
        history.capture(.text("keep")); history.togglePin(history.items[0].id)
        history.capture(.text("remove"))
        history.clearUnpinned()
        #expect(history.items.map(\.payload.preview) == ["keep"])
        history.clearAll()
        #expect(history.items.isEmpty)
    }
}
