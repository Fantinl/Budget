import XCTest
@testable import Budget

final class BulkTests: StoreTestCase {
    func testBulkRecategorize() {
        let store = makeStore()
        let a = expense(3, note: "A", on: day(2026, 10, 1)), b = expense(4, note: "B", on: day(2026, 10, 2)), c = expense(5, note: "C", on: day(2026, 10, 3))
        [a, b, c].forEach(store.upsert)
        XCTAssertEqual(store.updateTransactions(ids: [a.id, b.id]) { $0.categoryID = "restaurants" }, 2)
        XCTAssertEqual(store.transactions.filter { $0.categoryID == "restaurants" }.count, 2)
        XCTAssertEqual(store.transactions.first { $0.id == c.id }?.categoryID, "otherExpense")
        XCTAssertEqual(makeStore().transactions.filter { $0.categoryID == "restaurants" }.count, 2)
    }

    func testBulkUpdateWithUnknownIDsDoesNothing() {
        let store = makeStore()
        XCTAssertEqual(store.updateTransactions(ids: [UUID()]) { $0.amount = 1 }, 0)
    }

    func testBulkDelete() {
        let store = makeStore()
        let a = expense(3, on: day(2026, 10, 1)), b = expense(4, on: day(2026, 10, 2))
        store.upsert(a); store.upsert(b)
        XCTAssertEqual(store.deleteTransactions(ids: [a.id]), 1)
        XCTAssertEqual(store.transactions.map(\.id), [b.id])
        XCTAssertEqual(store.deleteTransactions(ids: [UUID()]), 0)
    }

    func testDuplicateKeepsFieldsAndDateButDropsRecurringLink() {
        let store = makeStore()
        var source = expense(3, "groceries", note: "Pain", on: day(2020, 1, 1))
        source.recurringID = UUID()
        store.upsert(source)
        let copies = store.duplicateTransactions(ids: [source.id])
        XCTAssertEqual(copies.count, 1)
        XCTAssertNotEqual(copies[0].id, source.id)
        XCTAssertEqual(copies[0].amount, 3)
        XCTAssertEqual(copies[0].note, "Pain")
        XCTAssertNil(copies[0].recurringID)
        XCTAssertEqual(copies[0].date, source.date) // la copie garde la date de l'original
        XCTAssertEqual(store.transactions.count, 2)
    }
}
