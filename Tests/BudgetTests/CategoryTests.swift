import XCTest
@testable import Budget

final class CategoryTests: StoreTestCase {
    func testDeleteUsedCategoryReassignsEverythingToOther() {
        let store = makeStore()
        store.upsert(expense(10, "groceries", on: day(2026, 10, 1)))
        store.recurringOperations = [RecurringOperation(name: "Loyer", amount: 700, kind: .expense, categoryID: "groceries", accountID: nil, note: "",
                                                        frequency: .monthly, startDate: day(2026, 1, 1), endDate: nil, isActive: true, lastGeneratedDate: nil)]
        store.upsertQuickExpense(QuickExpense(name: "Pain", amount: 1, categoryID: "groceries"))
        store.deleteCategory(store.category(id: "groceries"))
        XCTAssertFalse(store.transactions.contains { $0.categoryID == "groceries" })
        XCTAssertFalse(store.recurringOperations.contains { $0.categoryID == "groceries" })
        XCTAssertFalse(store.quickExpenses.contains { $0.categoryID == "groceries" })
        XCTAssertEqual(store.transactions[0].categoryID, "otherExpense")
        XCTAssertFalse(store.categories.contains { $0.id == "groceries" })
    }

    func testFallbackCategoriesCannotBeDeleted() {
        let store = makeStore()
        let other = store.category(id: "otherExpense")
        XCTAssertTrue(store.isProtected(other))
        store.deleteCategory(other)
        XCTAssertTrue(store.categories.contains { $0.id == "otherExpense" })
    }

    func testIncomeCategoryFallsBackToOtherIncome() {
        let store = makeStore()
        store.upsert(income(100, "salary", on: day(2026, 10, 1)))
        store.deleteCategory(store.category(id: "salary"))
        XCTAssertEqual(store.transactions[0].categoryID, "otherIncome")
    }

    func testUnknownCategoryReturnsPlaceholder() {
        let store = makeStore()
        XCTAssertEqual(store.category(id: "nope").label, "Sans catégorie")
    }

    func testUsageAndHiddenCategories() {
        let store = makeStore()
        store.upsert(expense(1, "leisure", on: day(2026, 10, 1)))
        let leisure = store.category(id: "leisure")
        XCTAssertEqual(store.usageCount(of: leisure), 1)
        XCTAssertTrue(store.isUsed(leisure))
        var hidden = leisure
        hidden.isHidden = true
        store.upsertCategory(hidden)
        XCTAssertFalse(store.categories(for: .expense).contains { $0.id == "leisure" })
        XCTAssertTrue(store.categories(for: .expense, includeHidden: true).contains { $0.id == "leisure" })
    }

    func testDeletePersists() {
        let store = makeStore()
        store.deleteCategory(store.category(id: "health"))
        XCTAssertFalse(makeStore().categories.contains { $0.id == "health" })
    }
}
