import XCTest
@testable import Budget

final class UndoTests: StoreTestCase {
    func testUndoRedoAddedTransaction() {
        let store = makeStore()
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) { store.upsert(expense(9, note: "Test", on: day(2026, 10, 1))) }
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(manager.undoActionName, "Modifier l’opération")
        manager.undo()
        XCTAssertEqual(store.transactions.count, 0)
        XCTAssertEqual(makeStore().transactions.count, 0, "l'annulation est enregistrée sur disque")
        manager.redo()
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(makeStore().transactions.count, 1)
    }

    func testUndoRestoresSettings() {
        let store = makeStore()
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) { store.deleteCategory(store.category(id: "health")) }
        XCTAssertFalse(store.categories.contains { $0.id == "health" })
        manager.undo()
        XCTAssertTrue(store.categories.contains { $0.id == "health" })
        XCTAssertTrue(makeStore().categories.contains { $0.id == "health" })
    }

    func testUndoDeleteRestoresTransactionAndTransferLegs() {
        let store = makeStore()
        let livret = Account(name: "L", kind: .livretA, colorIndex: 0)
        store.upsertAccount(livret)
        let id = store.createTransfer(from: Account.mainID, to: livret.id, amount: 10, date: day(2026, 10, 1), note: "")!
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) { store.deleteTransfer(id: id) }
        XCTAssertTrue(store.transactions.isEmpty)
        manager.undo()
        XCTAssertEqual(store.transactions.filter { $0.transferID == id }.count, 2)
    }

    func testNoUndoManagerIsHarmless() {
        let store = makeStore()
        store.undoManager = nil
        store.upsert(expense(1, on: day(2026, 10, 1)))
        XCTAssertEqual(store.transactions.count, 1)
    }

    func testBulkActionIsASingleUndoStep() {
        let store = makeStore()
        let a = expense(1, on: day(2026, 10, 1)), b = expense(2, on: day(2026, 10, 2))
        store.upsert(a); store.upsert(b)
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) { store.updateTransactions(ids: [a.id, b.id]) { $0.categoryID = "leisure" } }
        manager.undo()
        XCTAssertTrue(store.transactions.allSatisfy { $0.categoryID == "otherExpense" })
    }
}
