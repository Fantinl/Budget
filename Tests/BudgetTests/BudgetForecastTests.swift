import XCTest
@testable import Budget

final class BudgetForecastTests: StoreTestCase {
    private let now = day(2026, 10, 17)

    private func setBudget(_ store: BudgetStore, _ id: String, _ amount: Decimal) {
        var category = store.category(id: id)
        category.monthlyBudget = amount
        store.upsertCategory(category)
    }

    func testBudgetStates() {
        let store = makeStore()
        setBudget(store, "restaurants", 100)
        func state() -> BudgetState? { store.budgetStatus(for: store.category(id: "restaurants"), month: now)?.state }
        XCTAssertEqual(state(), .ok)
        store.upsert(expense(79, "restaurants", on: now))
        XCTAssertEqual(state(), .ok)
        store.upsert(expense(1, "restaurants", on: now))
        XCTAssertEqual(state(), .warning)
        store.upsert(expense(20, "restaurants", on: now))
        XCTAssertEqual(state(), .warning, "exactement 100 % n'est pas dépassé")
        store.upsert(expense(1, "restaurants", on: now))
        let status = store.budgetStatus(for: store.category(id: "restaurants"), month: now)
        XCTAssertEqual(status?.state, .exceeded)
        XCTAssertEqual(status?.overspent, 1)
        XCTAssertEqual(status?.remaining, -1)
    }

    func testBudgetIgnoresOtherMonthsAndTransfers() {
        let store = makeStore()
        setBudget(store, "restaurants", 100)
        store.upsert(expense(50, "restaurants", on: day(2026, 9, 30)))
        var transferLeg = expense(500, "restaurants", on: now)
        transferLeg.transferID = UUID()
        store.upsert(transferLeg)
        XCTAssertEqual(store.spent(in: store.category(id: "restaurants"), month: now), 0)
    }

    func testNoBudgetMeansNoStatus() {
        let store = makeStore()
        XCTAssertNil(store.budgetStatus(for: store.category(id: "restaurants"), month: now))
        XCTAssertNil(store.budgetStatus(for: store.category(id: "salary"), month: now))
        setBudget(store, "restaurants", 100)
        store.setMonthlyBudget(nil, for: store.category(id: "restaurants"))
        XCTAssertTrue(store.budgetedCategories.isEmpty)
    }

    func testBudgetTotalsAndOrdering() {
        let store = makeStore()
        setBudget(store, "restaurants", 100)
        setBudget(store, "groceries", 200)
        store.upsert(expense(90, "restaurants", on: now))
        store.upsert(expense(20, "groceries", on: now))
        let statuses = store.budgetStatuses(month: now)
        XCTAssertEqual(statuses.map(\.category.id), ["restaurants", "groceries"])
        let totals = store.budgetTotals(month: now)
        XCTAssertEqual(totals.spent, 110)
        XCTAssertEqual(totals.budget, 300)
        XCTAssertEqual(totals.remaining, 190)
    }

    func testDaysRemaining() {
        XCTAssertEqual(BudgetStore.daysRemaining(in: now, now: now), 15)       // 17 → 31 octobre
        XCTAssertEqual(BudgetStore.daysRemaining(in: day(2026, 10, 31), now: day(2026, 10, 31)), 1)
        XCTAssertEqual(BudgetStore.daysRemaining(in: day(2026, 9, 1), now: now), 0)
        XCTAssertEqual(BudgetStore.daysRemaining(in: day(2026, 11, 1), now: now), 30)
    }

    func testForecastCurrentExcludesTransfers() {
        let store = makeStore()
        let livret = Account(name: "L", kind: .livretA, colorIndex: 0)
        store.upsertAccount(livret)
        store.upsert(income(1000, on: day(2026, 10, 2)))
        store.upsert(expense(300, on: day(2026, 10, 3)))
        store.createTransfer(from: Account.mainID, to: livret.id, amount: 200, date: day(2026, 10, 4), note: "")
        XCTAssertEqual(store.monthForecast(now: now).current, 700)
    }

    func testForecastNeedsTwoMonthsOfHistory() {
        let store = makeStore()
        store.upsert(expense(300, on: day(2026, 9, 10)))
        XCTAssertNil(store.monthForecast(now: now).estimatedSpending)
        store.upsert(expense(300, on: day(2026, 8, 10)))
        let forecast = store.monthForecast(now: now)
        // 600 € sur août (31 j) + septembre (30 j) ; 15 jours restants, aujourd'hui exclu → 14.
        let daily = Decimal(600) / 61
        XCTAssertEqual(forecast.dailyAverage, daily)
        XCTAssertEqual(forecast.estimatedSpending, daily * 14)
    }

    func testForecastHistoryIgnoresRecurringOperations() {
        let store = makeStore()
        var rec = expense(300, on: day(2026, 9, 10)); rec.recurringID = UUID()
        store.upsert(rec)
        store.upsert(expense(300, on: day(2026, 8, 10)))
        XCTAssertNil(store.monthForecast(now: now).estimatedSpending)
    }

    func testUpcomingRecurringAndProjectedBalance() {
        let store = makeStore()
        store.recurringOperations = [
            RecurringOperation(name: "Loyer", amount: 700, kind: .expense, categoryID: "housing", accountID: nil, note: "",
                               frequency: .monthly, startDate: startOfDay(2026, 1, 25), endDate: nil, isActive: true, lastGeneratedDate: startOfDay(2026, 9, 25)),
            RecurringOperation(name: "Salaire", amount: 1800, kind: .income, categoryID: "salary", accountID: nil, note: "",
                               frequency: .monthly, startDate: startOfDay(2026, 1, 28), endDate: nil, isActive: true, lastGeneratedDate: nil),
            RecurringOperation(name: "Inactif", amount: 5, kind: .expense, categoryID: "housing", accountID: nil, note: "",
                               frequency: .monthly, startDate: startOfDay(2026, 1, 20), endDate: nil, isActive: false, lastGeneratedDate: nil),
        ]
        store.upsert(income(100, on: day(2026, 10, 1)))
        let upcoming = store.upcomingRecurring(now: now)
        XCTAssertEqual(upcoming.map(\.name), ["Loyer", "Salaire"])
        XCTAssertEqual(upcoming.map(\.amount), [-700, 1800])
        XCTAssertEqual(store.monthForecast(now: now).projected, 100 + 1100)
        XCTAssertEqual(store.projectedBalance(now: now), 100 + 1100)
    }

    func testNoUpcomingOnLastDayOfMonth() {
        let store = makeStore()
        store.recurringOperations = [RecurringOperation(name: "X", amount: 1, kind: .expense, categoryID: "housing", accountID: nil, note: "",
                                                        frequency: .monthly, startDate: startOfDay(2026, 1, 15), endDate: nil, isActive: true, lastGeneratedDate: nil)]
        XCTAssertTrue(store.upcomingRecurring(now: day(2026, 10, 31)).isEmpty)
    }
}
