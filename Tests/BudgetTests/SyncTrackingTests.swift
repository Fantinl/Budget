import XCTest
@testable import Budget

final class SyncTrackingTests: StoreTestCase {
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeTrackedStore() -> BudgetStore {
        let store = makeStore()
        store.sync.clock = { [unowned self] in self.now }
        return store
    }

    func tick() { now = now.addingTimeInterval(10) }

    func testUpsertAndDeleteTransaction() {
        let store = makeTrackedStore()
        let t = expense(5, note: "a", on: day(2026, 10, 1))
        let key = SyncKey.transaction + t.id.uuidString
        store.upsert(t)
        XCTAssertEqual(store.sync.meta.modifiedAt[key], now)
        tick()
        var edited = t; edited.note = "b"
        store.upsert(edited)
        XCTAssertEqual(store.sync.meta.modifiedAt[key], now)
        tick()
        store.upsert(edited)   // identique : pas de nouvelle date
        XCTAssertEqual(store.sync.meta.modifiedAt[key], now.addingTimeInterval(-10))
        store.delete(edited)
        XCTAssertEqual(store.sync.meta.deletedAt[key], now)
        XCTAssertNil(store.sync.meta.modifiedAt[key])
    }

    func testSettingsRecordsAndPersistence() {
        let store = makeTrackedStore()
        let tag = Tag(name: "vacances", colorIndex: 1)
        let quick = QuickExpense(name: "Thé", amount: 2, categoryID: "restaurants")
        store.upsertTag(tag)
        store.upsertQuickExpense(quick)
        XCTAssertEqual(store.sync.meta.modifiedAt[SyncKey.tag + tag.id], now)
        XCTAssertEqual(store.sync.meta.modifiedAt[SyncKey.quick + quick.id.uuidString], now)
        tick()
        store.deleteQuickExpense(quick)
        XCTAssertEqual(store.sync.meta.deletedAt[SyncKey.quick + quick.id.uuidString], now)
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.sync.meta, store.sync.meta, "les métadonnées survivent au redémarrage")
    }

    func testDeletingCategoryStampsReassignedRecords() {
        let store = makeTrackedStore()
        let t = expense(5, "health", on: day(2026, 10, 1))
        store.upsert(t)
        tick()
        store.deleteCategory(store.category(id: "health"))
        XCTAssertEqual(store.sync.meta.deletedAt[SyncKey.category + "health"], now)
        XCTAssertEqual(store.sync.meta.modifiedAt[SyncKey.transaction + t.id.uuidString], now)
    }

    func testReorderStampsOnlyOrder() {
        let store = makeTrackedStore()
        let first = store.quickExpenses[0]
        store.moveQuickExpenses(from: IndexSet(integer: 0), to: store.quickExpenses.count)
        XCTAssertEqual(store.sync.meta.settingsAt[SyncKey.orderQuick], now)
        XCTAssertNil(store.sync.meta.modifiedAt[SyncKey.quick + first.id.uuidString])
        tick()
        store.upsertQuickExpense(QuickExpense(name: "Neuf", amount: 1, categoryID: "groceries"))
        XCTAssertEqual(store.sync.meta.settingsAt[SyncKey.orderQuick], now.addingTimeInterval(-10), "un ajout ne change pas l'ordre relatif")
    }

    func testDefaultAccountStamp() {
        let store = makeTrackedStore()
        let livret = Account(name: "Livret", kind: .livretA, colorIndex: 1)
        store.upsertAccount(livret)
        tick()
        store.setDefaultAccount(livret)
        XCTAssertEqual(store.sync.meta.settingsAt[SyncKey.defaultAccount], now)
    }

    func testFirstLaunchWithoutMetadataUsesFileDates() throws {
        let store = makeStore()
        let t = expense(5, on: day(2026, 10, 1))
        store.upsert(t)
        store.upsertTag(Tag(name: "x", colorIndex: 0))
        let fileDate = Date(timeIntervalSince1970: 1_700_000_000)
        for url in [store.transactionsURL, store.settingsURL] {
            try FileManager.default.setAttributes([.modificationDate: fileDate], ofItemAtPath: url.path)
        }
        try FileManager.default.removeItem(at: store.syncMetaURL)
        let fresh = makeStore()
        let stamp = try XCTUnwrap(fresh.sync.meta.modifiedAt[SyncKey.transaction + t.id.uuidString])
        XCTAssertEqual(stamp.timeIntervalSince1970, fileDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(fresh.sync.meta.modifiedAt[SyncKey.category + "groceries"], stamp)
        XCTAssertNotNil(fresh.sync.meta.settingsAt[SyncKey.orderCategories])
    }

    func testBrandNewStoreHasNoMetadata() {
        XCTAssertTrue(makeStore().isSyncPristine)
    }

    func testRestoreCountsAsModification() {
        let store = makeTrackedStore()
        let t = expense(5, on: day(2026, 10, 1))
        store.upsert(t)
        store.backupNow()
        tick()
        store.delete(t)
        tick()
        let backup = store.listBackups()[0]
        XCTAssertTrue(store.restore(backup))
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.sync.meta.modifiedAt[SyncKey.transaction + t.id.uuidString], now)
        XCTAssertNil(store.sync.meta.deletedAt[SyncKey.transaction + t.id.uuidString])
    }
}
