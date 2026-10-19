import XCTest
@testable import Budget

final class ReorderTests: StoreTestCase {
    private func names(_ store: BudgetStore) -> String { store.quickExpenses.map(\.name).joined() }

    private func storeWithQuickExpenses() -> BudgetStore {
        let store = makeStore()
        store.quickExpenses = []
        for n in ["A", "B", "C"] { store.upsertQuickExpense(QuickExpense(name: n, amount: 1, categoryID: "otherExpense")) }
        return store
    }

    func testMoveDestinations() {
        XCTAssertEqual(ReorderMove.up.destination(from: 1, count: 3), 0)
        XCTAssertEqual(ReorderMove.up.destination(from: 0, count: 3), 0)
        XCTAssertEqual(ReorderMove.down.destination(from: 0, count: 3), 2)
        XCTAssertEqual(ReorderMove.down.destination(from: 2, count: 3), 3)
        XCTAssertEqual(ReorderMove.first.destination(from: 2, count: 3), 0)
        XCTAssertEqual(ReorderMove.last.destination(from: 0, count: 3), 3)
    }

    func testQuickExpenseReordering() {
        let store = storeWithQuickExpenses()
        store.moveQuickExpenses(from: [1], to: ReorderMove.up.destination(from: 1, count: 3))
        XCTAssertEqual(names(store), "BAC")
        store.moveQuickExpenses(from: [0], to: ReorderMove.down.destination(from: 0, count: 3))
        XCTAssertEqual(names(store), "ABC")
        store.moveQuickExpenses(from: [0], to: ReorderMove.last.destination(from: 0, count: 3))
        XCTAssertEqual(names(store), "BCA")
        store.moveQuickExpenses(from: [2], to: ReorderMove.first.destination(from: 2, count: 3))
        XCTAssertEqual(names(store), "ABC")
        XCTAssertEqual(BudgetStore(directory: dir).quickExpenses.map(\.name).joined(), "ABC", "ordre enregistré")
    }

    func testCategoryReorderingStaysWithinKind() {
        let store = makeStore()
        for n in ["X", "Y", "Z"] { store.upsertCategory(Category(label: n, icon: "tag", kind: .expense, colorIndex: 0)) }
        let expenses = store.categories(for: .expense)
        let incomeBefore = store.categories(for: .income).map(\.id)
        store.moveCategories(of: .expense, from: [expenses.count - 1], to: ReorderMove.first.destination(from: expenses.count - 1, count: expenses.count))
        XCTAssertEqual(store.categories(for: .expense).first?.id, expenses.last?.id)
        XCTAssertEqual(store.categories(for: .expense).count, expenses.count)
        XCTAssertEqual(store.categories(for: .income).map(\.id), incomeBefore)
    }

    func testAccountReordering() {
        let store = makeStore()
        store.upsertAccount(Account(id: "a", name: "A", kind: .livretA, colorIndex: 0))
        store.upsertAccount(Account(id: "b", name: "B", kind: .ldds, colorIndex: 0))
        XCTAssertEqual(store.accounts.map(\.id), ["main", "a", "b"])
        store.moveAccounts(from: [2], to: 1)
        XCTAssertEqual(store.accounts.map(\.id), ["main", "b", "a"])
        XCTAssertEqual(makeStore().accounts.map(\.id), ["main", "b", "a"])
    }
}
