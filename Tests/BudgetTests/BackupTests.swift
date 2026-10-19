import XCTest
@testable import Budget

final class BackupTests: StoreTestCase {
    func testBackupThenRestore() {
        let store = makeStore()
        store.upsert(expense(1, on: day(2026, 10, 1)))
        store.upsert(expense(2, on: day(2026, 10, 2)))
        XCTAssertTrue(store.backupNow())
        store.transactions.removeAll()
        store.saveTransactions()
        let backups = store.listBackups()
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].transactionCount, 2)
        XCTAssertTrue(store.restore(backups[0]))
        XCTAssertEqual(store.transactions.count, 2)
        // L'état courant (vide) a été sauvegardé avant la restauration.
        XCTAssertGreaterThanOrEqual(store.listBackups().count, 2)
    }

    func testBackupWithoutDataFails() {
        let store = makeStore()
        XCTAssertFalse(store.backupNow())
        XCTAssertNotNil(store.errorMessage)
    }

    func testAutomaticBackupOnlyEveryDay() {
        let store = makeStore()
        store.upsert(expense(1, on: day(2026, 10, 1)))
        let t0 = day(2026, 10, 1)
        store.backupIfNeeded(now: t0)
        XCTAssertEqual(store.listBackups().count, 1)
        store.backupIfNeeded(now: t0.addingTimeInterval(3600))
        XCTAssertEqual(store.listBackups().count, 1)
    }

    func testOldBackupsArePruned() {
        let store = makeStore()
        store.upsert(expense(1, on: day(2026, 10, 1)))
        for i in 0..<(BudgetStore.maxBackups + 3) {
            store.backupIfNeeded(now: day(2026, 1, 1).addingTimeInterval(Double(i) * 2 * 86_400))
        }
        XCTAssertEqual(store.listBackups().count, BudgetStore.maxBackups)
    }

    func testUnreadableBackupDoesNotTouchData() throws {
        let store = makeStore()
        store.upsert(expense(1, on: day(2026, 10, 1)))
        XCTAssertTrue(store.backupNow())
        let backup = store.listBackups()[0]
        try "cassé".write(to: backup.url.appending(path: "transactions.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(store.restore(backup))
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertNotNil(store.errorMessage)
    }

    func testExportAndImportFile() throws {
        let store = makeStore()
        store.upsert(expense(5, "groceries", note: "Pain", on: day(2026, 10, 1)))
        store.upsertAccount(Account(name: "Livret", kind: .livretA, colorIndex: 1, initialBalance: 10))
        let file = dir.appending(path: "export.json")
        XCTAssertTrue(store.exportBackup(to: file))

        let otherDir = dir.appending(path: "other", directoryHint: .isDirectory)
        let other = BudgetStore(directory: otherDir)
        XCTAssertTrue(other.importBackup(from: file))
        XCTAssertEqual(other.transactions, store.transactions)
        XCTAssertEqual(other.accounts, store.accounts)
        XCTAssertEqual(BudgetStore(directory: otherDir).transactions.count, 1)
    }

    func testImportInvalidFileKeepsData() throws {
        let store = makeStore()
        store.upsert(expense(5, on: day(2026, 10, 1)))
        let file = dir.appending(path: "bad.json")
        try "{}".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(store.importBackup(from: file))
        XCTAssertEqual(store.transactions.count, 1)
    }
}
