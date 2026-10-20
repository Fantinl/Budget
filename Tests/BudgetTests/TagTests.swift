import XCTest
@testable import Budget

@MainActor
final class TagTests: StoreTestCase {
    func testAddTagDeduplicatesByName() {
        let store = makeStore()
        let a = store.addTag(named: "Vacances")
        let b = store.addTag(named: "  #vacances ")
        let c = store.addTag(named: "Café")
        let d = store.addTag(named: "cafe")
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(c.id, d.id)
        XCTAssertEqual(store.tags.count, 2)
        XCTAssertEqual(a.name, "Vacances")
    }

    func testDeleteTagRemovesItFromTransactions() {
        let store = makeStore()
        let keep = store.addTag(named: "a")
        let gone = store.addTag(named: "b")
        var t1 = expense(10, on: day(2026, 1, 1)); t1.tagIDs = [gone.id]
        var t2 = expense(5, on: day(2026, 1, 2)); t2.tagIDs = [keep.id, gone.id]
        store.upsert(t1); store.upsert(t2)
        XCTAssertEqual(store.usageCount(of: gone), 2)
        store.deleteTag(gone)
        XCTAssertEqual(store.transactions.count, 2)
        XCTAssertNil(store.transactions.first { $0.id == t1.id }?.tagIDs)
        XCTAssertEqual(store.transactions.first { $0.id == t2.id }?.tagIDs, [keep.id])
        XCTAssertEqual(store.tags.map(\.id), [keep.id])
    }

    func testTagsOfTransactionFollowStoreOrderAndIgnoreUnknown() {
        let store = makeStore()
        let a = store.addTag(named: "a"), b = store.addTag(named: "b")
        var t = expense(1, on: day(2026, 1, 1)); t.tagIDs = [b.id, "inconnu", a.id]
        XCTAssertEqual(store.tags(of: t).map(\.id), [a.id, b.id])
    }

    func testMoveTags() {
        let store = makeStore()
        let a = store.addTag(named: "a"), b = store.addTag(named: "b"), c = store.addTag(named: "c")
        store.moveTags(from: [2], to: 0)
        XCTAssertEqual(store.tags.map(\.id), [c.id, a.id, b.id])
    }

    func testFilterByTag() {
        let store = makeStore()
        let a = store.addTag(named: "a"), b = store.addTag(named: "b")
        var t1 = expense(1, on: day(2026, 1, 1)); t1.tagIDs = [a.id]
        var t2 = expense(1, on: day(2026, 1, 1)); t2.tagIDs = [b.id]
        let t3 = expense(1, on: day(2026, 1, 1))
        var filter = OperationFilter()
        XCTAssertFalse(filter.isActive)
        filter.tagIDs = [a.id, b.id]
        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.matches(t1))
        XCTAssertTrue(filter.matches(t2))
        XCTAssertFalse(filter.matches(t3))
        filter.tagIDs = [a.id]
        XCTAssertFalse(filter.matches(t2))
    }

    func testPersistence() {
        let store = makeStore()
        let tag = store.addTag(named: "Cadeau")
        var t = expense(12, on: day(2026, 2, 1)); t.tagIDs = [tag.id]
        store.upsert(t)
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.tags, [tag])
        XCTAssertEqual(reloaded.transactions.first?.tagIDs, [tag.id])
    }

    func testUndoDeleteTag() {
        let store = makeStore()
        let manager = attachUndoManager(to: store)
        var tag = Tag(name: "x", colorIndex: 0)
        inUndoGroup(manager) { tag = store.addTag(named: "x") }
        var t = expense(3, on: day(2026, 3, 1)); t.tagIDs = [tag.id]
        inUndoGroup(manager) { store.upsert(t) }
        inUndoGroup(manager) { store.deleteTag(tag) }
        XCTAssertTrue(store.tags.isEmpty)
        manager.undo()
        XCTAssertEqual(store.tags, [tag])
        XCTAssertEqual(store.transactions.first?.tagIDs, [tag.id])
    }

    func testOldSettingsWithoutTagsKey() throws {
        try write(#"{"categories": []}"#, as: "settings.json")
        let store = makeStore()
        XCTAssertTrue(store.tags.isEmpty)
    }
}
