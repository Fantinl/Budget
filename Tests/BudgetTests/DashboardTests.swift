import XCTest
@testable import Budget

final class DashboardTests: StoreTestCase {
    private let now = day(2026, 10, 17)

    func testAvailableMoneyCountsOnlyCurrentAccounts() {
        let store = makeStore()
        store.upsertAccount(Account(name: "Livret", kind: .livretA, colorIndex: 1, initialBalance: 500))
        store.upsertAccount(Account(name: "Pocket", kind: .cash, colorIndex: 2, initialBalance: 40))
        store.upsert(income(1000, on: now))
        store.upsert(expense(200, on: now))
        let summary = DashboardSummary(store: store, now: now)
        XCTAssertEqual(summary.available, 800)
        XCTAssertEqual(summary.currentAccounts.count, 1)
        XCTAssertEqual(summary.savings, 500)
        XCTAssertEqual(summary.wealth, 1340)
    }

    func testArchivedCurrentAccountIsIgnored() {
        let store = makeStore()
        let second = Account(name: "Second", kind: .checking, colorIndex: 1, initialBalance: 300)
        store.upsertAccount(second)
        XCTAssertEqual(DashboardSummary(store: store, now: now).available, 300)
        store.archiveAccount(second)
        XCTAssertEqual(DashboardSummary(store: store, now: now).available, 0)
    }

    func testMonthRemainingExcludesTransfers() {
        let store = makeStore()
        var out = expense(100, "otherExpense", on: now)
        out.transferID = UUID()
        var inn = income(100, on: now, account: "x")
        inn.transferID = out.transferID
        store.upsert(out)
        store.upsert(inn)
        store.upsert(income(1000, on: now))
        store.upsert(expense(250, on: now))
        let summary = DashboardSummary(store: store, now: now)
        XCTAssertEqual(summary.monthIncome, 1000)
        XCTAssertEqual(summary.monthSpent, 250)
        XCTAssertEqual(summary.monthRemaining, 750)
    }

    func testIzlyMealsRemaining() {
        let store = makeStore()
        XCTAssertNil(DashboardSummary(store: store, now: now).izly)
        var izly = Account(name: "Izly", kind: .izly, colorIndex: 3, initialBalance: 12)
        izly.mealPlan = MealPlan(price: 3)
        store.upsertAccount(izly)
        var summary = DashboardSummary(store: store, now: now)
        XCTAssertEqual(summary.izly?.meals, 4)
        XCTAssertTrue(summary.izlyIsLow)

        izly.mealPlan = nil
        izly.initialBalance = 20
        store.upsertAccount(izly)
        summary = DashboardSummary(store: store, now: now)
        XCTAssertEqual(summary.izly?.meals, 20)
        XCTAssertFalse(summary.izlyIsLow)
        // Le compte Izly n'entre pas dans l'argent disponible
        XCTAssertEqual(summary.available, 0)
    }

    func testBudgetsTopThreeAndTotals() {
        let store = makeStore()
        XCTAssertNil(DashboardSummary(store: store, now: now).budgetTotals)
        for id in ["restaurants", "groceries", "transport", "leisure"] {
            var c = store.category(id: id)
            c.monthlyBudget = 100
            store.upsertCategory(c)
        }
        store.upsert(expense(50, "restaurants", on: now))
        let summary = DashboardSummary(store: store, now: now)
        XCTAssertLessThanOrEqual(summary.topBudgets.count, 3)
        XCTAssertEqual(summary.topBudgets.first?.category.id, "restaurants")
        XCTAssertEqual(summary.budgetTotals?.spent, 50)
    }

    func testUpcomingWithin30DaysAndLatest() {
        let store = makeStore()
        let rent = RecurringOperation(name: "Loyer", amount: 500, kind: .expense, categoryID: "otherExpense",
                                      accountID: nil, note: "", frequency: .monthly,
                                      startDate: startOfDay(2026, 10, 25), endDate: nil, isActive: true,
                                      lastGeneratedDate: nil)
        store.recurringOperations = [rent]
        for i in 1...7 { store.upsert(expense(Decimal(i), on: day(2026, 10, i))) }
        let summary = DashboardSummary(store: store, now: now)
        XCTAssertEqual(summary.upcoming.map(\.name), ["Loyer"])
        XCTAssertEqual(summary.upcoming.first?.amount, -500)
        XCTAssertEqual(summary.latest.count, 5)
        XCTAssertEqual(summary.latest.first?.amount, 7)
    }
}
