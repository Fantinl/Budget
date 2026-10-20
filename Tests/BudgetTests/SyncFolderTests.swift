import XCTest
@testable import Budget

final class SyncFolderTests: StoreTestCase {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var cloud: URL!
    var storeA: BudgetStore!
    var storeB: BudgetStore!
    var syncA: SyncCoordinator!
    var syncB: SyncCoordinator!

    override func setUp() {
        super.setUp()
        func folder(_ name: String) -> URL {
            let url = dir.appending(path: name, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        cloud = folder("icloud")
        storeA = BudgetStore(directory: folder("A"))
        storeB = BudgetStore(directory: folder("B"))
        for store in [storeA!, storeB!] { store.sync.clock = { [unowned self] in self.now } }
        syncA = makeCoordinator(storeA, suite: "A")
        syncB = makeCoordinator(storeB, suite: "B")
    }

    func makeCoordinator(_ store: BudgetStore, suite: String) -> SyncCoordinator {
        let defaults = UserDefaults(suiteName: "BudgetSyncTests-\(suite)-\(UUID().uuidString)")!
        return SyncCoordinator(store: store, defaults: defaults, transport: FolderSyncTransport(folderURL: cloud))
    }

    func tick(_ seconds: TimeInterval = 10) { now = now.addingTimeInterval(seconds) }

    func testAddOnAAppearsOnB() async {
        let t = expense(12, note: "Pain", on: day(2026, 10, 1))
        storeA.upsert(t)
        await syncA.syncNow()
        XCTAssertNil(syncA.lastError)
        await syncB.syncNow()
        XCTAssertNil(syncB.lastError)
        XCTAssertEqual(storeB.transactions, [t])
        XCTAssertNotNil(syncB.lastSync)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appending(path: "Budget-sync.json").path))
    }

    func testDeleteOnBDisappearsOnA() async {
        let t = expense(12, on: day(2026, 10, 1))
        storeA.upsert(t)
        await syncA.syncNow(); await syncB.syncNow()
        tick()
        storeB.delete(t)
        await syncB.syncNow(); await syncA.syncNow()
        XCTAssertTrue(storeA.transactions.isEmpty)
        // Et rien ne ressuscite au tour suivant.
        await syncB.syncNow(); await syncA.syncNow()
        XCTAssertTrue(storeA.transactions.isEmpty)
        XCTAssertTrue(storeB.transactions.isEmpty)
    }

    func testConcurrentEditsAreResolved() async {
        let t = expense(12, note: "origine", on: day(2026, 10, 1))
        storeA.upsert(t)
        await syncA.syncNow(); await syncB.syncNow()
        tick()
        var editA = t; editA.note = "depuis A"
        storeA.upsert(editA)
        storeA.upsertTag(Tag(id: "ta", name: "a", colorIndex: 0))
        tick()
        var editB = t; editB.note = "depuis B"
        storeB.upsert(editB)
        storeB.upsertTag(Tag(id: "tb", name: "b", colorIndex: 1))
        await syncA.syncNow()
        await syncB.syncNow()
        await syncA.syncNow()
        XCTAssertEqual(storeA.transactions.first?.note, "depuis B")
        XCTAssertEqual(storeB.transactions.first?.note, "depuis B")
        XCTAssertEqual(Set(storeA.tags.map(\.id)), ["ta", "tb"])
        XCTAssertEqual(Set(storeB.tags.map(\.id)), ["ta", "tb"])
    }

    func testSyncPersistsOnDiskWithoutFakeChanges() async {
        storeA.upsert(expense(1, on: day(2026, 10, 1)))
        await syncA.syncNow(); await syncB.syncNow()
        let stampsBefore = storeB.sync.meta.modifiedAt
        await syncB.syncNow()
        XCTAssertEqual(storeB.sync.meta.modifiedAt, stampsBefore)
        XCTAssertEqual(BudgetStore(directory: storeB.directory).transactions, storeB.transactions)
    }

    func testUndoAfterSyncDoesNotCrashAndIsCleared() async {
        let manager = attachUndoManager(to: storeA)
        inUndoGroup(manager) { storeA.upsert(expense(3, on: day(2026, 10, 1))) }
        await syncA.syncNow()
        tick()
        storeB.upsert(expense(4, note: "de B", on: day(2026, 10, 2)))
        await syncB.syncNow()
        await syncA.syncNow()
        XCTAssertEqual(storeA.transactions.count, 2)
        XCTAssertFalse(manager.canUndo, "l'historique est vidé quand une synchro change les données")
        manager.undo()
        XCTAssertEqual(storeA.transactions.count, 2)
        // Un ⌘Z sans synchro entre-temps reste possible.
        tick()
        inUndoGroup(manager) { storeA.upsert(expense(5, on: day(2026, 10, 3))) }
        await syncA.syncNow()
        manager.undo()
        XCTAssertEqual(storeA.transactions.count, 2)
    }

    func testUnreadableRemoteFileIsReportedAndKept() async throws {
        let file = cloud.appending(path: "Budget-sync.json")
        try "pas du json".write(to: file, atomically: true, encoding: .utf8)
        storeA.upsert(expense(1, on: day(2026, 10, 1)))
        await syncA.syncNow()
        XCTAssertNotNil(syncA.lastError)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "pas du json")
    }

    func testDefaultsAreNotDuplicatedOnNewDevice() async {
        storeA.upsertQuickExpense(QuickExpense(name: "Thé", amount: 2, categoryID: "restaurants"))
        await syncA.syncNow(); await syncB.syncNow()
        XCTAssertEqual(storeB.quickExpenses.map(\.id), storeA.quickExpenses.map(\.id))
        XCTAssertEqual(storeB.categories.count, storeA.categories.count)
    }
}
