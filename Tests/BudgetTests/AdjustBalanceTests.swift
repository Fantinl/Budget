import XCTest
@testable import Budget

final class AdjustBalanceTests: StoreTestCase {
    private func makeIzly(_ store: BudgetStore) -> Account {
        let izly = Account(name: "Izly", kind: .izly, colorIndex: 1, initialBalance: 20)
        store.accounts.append(izly)
        return izly
    }

    func testLowerBalanceCreatesExpense() {
        let store = makeStore()
        let izly = makeIzly(store)
        let t = store.adjustBalance(of: izly, to: 13, categoryID: "restaurants", note: "Repas")
        XCTAssertEqual(t?.kind, .expense)
        XCTAssertEqual(t?.amount, 7)
        XCTAssertEqual(t?.categoryID, "restaurants")
        XCTAssertEqual(t?.accountID, izly.id)
        XCTAssertEqual(store.balance(of: izly), 13)
        XCTAssertEqual(store.transactions(of: izly).count, 1)
    }

    func testHigherBalanceCreatesIncomeInOtherIncome() {
        let store = makeStore()
        let izly = makeIzly(store)
        store.adjustBalance(of: izly, to: 13, categoryID: "restaurants", note: "")
        let r = store.adjustBalance(of: izly, to: 15, categoryID: "restaurants", note: "Rembours")
        XCTAssertEqual(r?.kind, .income)
        XCTAssertEqual(r?.amount, 2)
        XCTAssertEqual(r?.categoryID, "otherIncome")
        XCTAssertEqual(store.balance(of: izly), 15)
    }

    func testSameBalanceDoesNothing() {
        let store = makeStore()
        let izly = makeIzly(store)
        XCTAssertNil(store.adjustBalance(of: izly, to: 20, categoryID: "restaurants", note: ""))
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testGapIsComputedAsOfDate() {
        let store = makeStore()
        let izly = makeIzly(store)
        store.upsert(expense(5, on: day(2026, 10, 10), account: izly.id))
        XCTAssertEqual(store.balanceGap(of: izly, to: 15, asOf: day(2026, 10, 12)), 0)
        XCTAssertEqual(store.balanceGap(of: izly, to: 15, asOf: day(2026, 10, 1)), -5)
    }

    func testMainAccountAdjustmentStoresNilAccountID() {
        let store = makeStore()
        let t = store.adjustBalance(of: .main, to: 50, categoryID: "otherExpense", note: "")
        XCTAssertNil(t?.accountID)
        XCTAssertEqual(store.balance(of: .main), 50)
    }

    func testUndoAdjustment() {
        let store = makeStore()
        let izly = makeIzly(store)
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) { store.adjustBalance(of: izly, to: 10, categoryID: "restaurants", note: "x") }
        XCTAssertEqual(store.balance(of: izly), 10)
        XCTAssertEqual(manager.undoActionName, "Ajuster le solde")
        manager.undo()
        XCTAssertEqual(store.balance(of: izly), 20)
        XCTAssertTrue(store.transactions.isEmpty)
    }
}
