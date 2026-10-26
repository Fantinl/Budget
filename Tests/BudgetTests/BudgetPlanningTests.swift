import XCTest
@testable import Budget

final class BudgetPlanningTests: StoreTestCase {
    private let now = day(2026, 10, 17)

    private func setBudget(_ store: BudgetStore, _ id: String, _ amount: Decimal, rollover: Bool = false) {
        var category = store.category(id: id)
        category.monthlyBudget = amount
        category.budgetRollover = rollover ? true : nil
        store.upsertCategory(category)
    }

    private func recurring(_ name: String, _ amount: Decimal, kind: TransactionKind = .expense,
                           category: String = "otherExpense", start: Date) -> RecurringOperation {
        RecurringOperation(name: name, amount: amount, kind: kind, categoryID: category, accountID: nil, note: "",
                           frequency: .monthly, startDate: start, endDate: nil, isActive: true, lastGeneratedDate: nil)
    }

    // MARK: - Budget du mois

    func testMonthOverrideTakesPrecedence() {
        let store = makeStore()
        setBudget(store, "restaurants", 100)
        store.setBudgetOverride(150, for: store.category(id: "restaurants"), month: now)
        XCTAssertEqual(store.plannedBudget(for: store.category(id: "restaurants"), month: now), 150)
        XCTAssertEqual(store.plannedBudget(for: store.category(id: "restaurants"), month: day(2026, 11, 1)), 100)

        // Un budget identique au budget par défaut n'est pas gardé.
        store.setBudgetOverride(100, for: store.category(id: "restaurants"), month: now)
        XCTAssertNil(store.category(id: "restaurants").budgetOverrides)

        // 0 = pas de budget ce mois-là.
        store.setBudgetOverride(0, for: store.category(id: "restaurants"), month: now)
        XCTAssertNil(store.budgetStatus(for: store.category(id: "restaurants"), month: now))
        XCTAssertFalse(store.budgetedCategories(month: now).contains { $0.id == "restaurants" })
    }

    func testOverrideAloneMakesCategoryBudgeted() {
        let store = makeStore()
        store.setBudgetOverride(80, for: store.category(id: "leisure"), month: now)
        XCTAssertEqual(store.budgetStatus(for: store.category(id: "leisure"), month: now)?.budget, 80)
        XCTAssertNil(store.budgetStatus(for: store.category(id: "leisure"), month: day(2026, 11, 1)))
    }

    func testRemoveBudgetClearsEverything() {
        let store = makeStore()
        setBudget(store, "restaurants", 100, rollover: true)
        store.setBudgetOverride(50, for: store.category(id: "restaurants"), month: day(2026, 12, 1))
        store.removeBudget(for: store.category(id: "restaurants"))
        let category = store.category(id: "restaurants")
        XCTAssertNil(category.monthlyBudget)
        XCTAssertNil(category.budgetOverrides)
        XCTAssertNil(category.budgetRollover)
    }

    // MARK: - Report

    func testRolloverCarriesSurplusAndDeficitWithinYear() {
        let store = makeStore()
        setBudget(store, "restaurants", 100, rollover: true)
        store.upsert(expense(10, on: day(2026, 8, 3)))          // l'app est utilisée depuis août
        store.upsert(expense(60, "restaurants", on: day(2026, 8, 10)))   // +40
        store.upsert(expense(130, "restaurants", on: day(2026, 9, 10)))  // -30
        let status = store.budgetStatus(for: store.category(id: "restaurants"), month: now)
        XCTAssertEqual(status?.carryOver, 10)
        XCTAssertEqual(status?.budget, 110)

        // Sans report, le budget reste 100.
        store.setBudgetRollover(false, for: store.category(id: "restaurants"))
        XCTAssertEqual(store.budgetStatus(for: store.category(id: "restaurants"), month: now)?.budget, 100)
    }

    func testRolloverResetsInJanuaryAndNeverGoesNegative() {
        let store = makeStore()
        setBudget(store, "restaurants", 100, rollover: true)
        store.upsert(expense(400, "restaurants", on: day(2026, 12, 10)))
        XCTAssertEqual(store.budgetStatus(for: store.category(id: "restaurants"), month: day(2027, 1, 5))?.carryOver, 0)

        store.upsert(expense(400, "restaurants", on: day(2026, 9, 10)))
        let october = store.budgetStatus(for: store.category(id: "restaurants"), month: now)
        XCTAssertEqual(october?.carryOver, -300)
        XCTAssertEqual(october?.budget, 0, "un report négatif ne rend pas le budget négatif")
        XCTAssertEqual(october?.state, .ok)
        store.upsert(expense(5, "restaurants", on: now))
        XCTAssertEqual(store.budgetStatus(for: store.category(id: "restaurants"), month: now)?.state, .exceeded)
    }

    // MARK: - Équilibre annuel

    func testAnnualBalanceDetectsRecovery() {
        let store = makeStore()
        setBudget(store, "restaurants", 100)
        store.upsert(expense(150, "restaurants", on: day(2026, 8, 10)))  // -50
        store.upsert(expense(40, "restaurants", on: day(2026, 9, 10)))   // +60
        store.upsert(expense(80, "restaurants", on: day(2026, 10, 10)))  // +20 (en cours)
        let balance = store.annualBudgetBalance(year: now, now: now)
        let row = balance.rows.first { $0.id == "restaurants" }
        XCTAssertEqual(row?.counted.count, 3, "janvier → juillet : l'app n'était pas encore utilisée")
        XCTAssertEqual(row?.balance, 30)
        XCTAssertEqual(row?.trend, .recovered)
        XCTAssertEqual(row?.exceededMonths, 1)
        XCTAssertEqual(row?.cells.filter(\.isFuture).count, 2)
        XCTAssertEqual(row?.runningBalance.map(\.balance), [-50, 10, 30])
        XCTAssertEqual(balance.total.balance, 30)
    }

    func testCatchUpPerMonth() {
        let store = makeStore()
        setBudget(store, "restaurants", 100)
        store.upsert(expense(300, "restaurants", on: day(2026, 10, 10)))  // -200
        let row = store.annualBudgetBalance(year: now, now: now).rows.first { $0.id == "restaurants" }
        XCTAssertEqual(row?.trend, .behind)
        // 2 mois restants à 100 € : il faut dépenser 0 € par mois pour rattraper 200 €.
        XCTAssertEqual(row?.catchUpPerMonth, 0)
    }

    // MARK: - Plan du mois

    func testMonthPlanExcludesBudgetedRecurringFromFixedCharges() {
        let store = makeStore()
        setBudget(store, "restaurants", 200)
        store.recurringOperations = [
            recurring("Salaire", 1500, kind: .income, category: "salary", start: day(2026, 1, 1)),
            recurring("Loyer", 600, category: "housing", start: day(2026, 1, 5)),
            recurring("Cantine", 50, category: "restaurants", start: day(2026, 1, 2)),
        ]
        store.setBudgetPlan(BudgetPlan(savingsGoal: 300))
        let plan = store.monthPlan(month: now, now: now)
        XCTAssertEqual(plan.incomeSource, .recurring)
        XCTAssertEqual(plan.expectedIncome, 1500)
        XCTAssertEqual(plan.fixedCharges.map(\.name), ["Loyer"])
        XCTAssertEqual(plan.envelopes, 200)
        XCTAssertEqual(plan.unallocated, 1500 - 600 - 200 - 300)

        store.setBudgetPlan(BudgetPlan(savingsGoal: 300, expectedIncome: 2000))
        XCTAssertEqual(store.monthPlan(month: now, now: now).incomeSource, .manual)
        XCTAssertEqual(store.monthPlan(month: now, now: now).unallocated, 900)
    }

    func testMonthPlanFallsBackToAverageIncome() {
        let store = makeStore()
        store.upsert(income(1000, on: day(2026, 8, 1)))
        store.upsert(income(1200, on: day(2026, 9, 1)))
        let plan = store.monthPlan(month: now, now: now)
        XCTAssertEqual(plan.incomeSource, .average)
        XCTAssertEqual(plan.expectedIncome, 1100)
    }

    func testBudgetPlanIsSavedAndUndoable() {
        let store = makeStore()
        let undo = attachUndoManager(to: store)
        inUndoGroup(undo) { store.setBudgetPlan(BudgetPlan(savingsGoal: 250)) }
        XCTAssertEqual(makeStore().budgetPlan.savingsGoal, 250)
        undo.undo()
        XCTAssertNil(store.budgetPlan.savingsGoal)
    }

    // MARK: - Projection et suggestions

    func testProjectionUsesPaceAndUpcomingRecurring() {
        let store = makeStore()
        store.upsert(expense(34, "groceries", on: day(2026, 10, 5)))     // 34 € en 17 jours = 2 €/jour
        store.recurringOperations = [recurring("Panier bio", 20, category: "groceries", start: day(2026, 1, 25))]
        let projected = store.projectedSpending(for: store.category(id: "groceries"), month: now, now: now)
        // 34 + 2 × 14 jours restants + 20 (récurrente du 25)
        XCTAssertEqual(projected, 82)
        XCTAssertNil(store.projectedSpending(for: store.category(id: "groceries"), month: day(2026, 9, 1), now: now))
    }

    func testSuggestions() {
        let store = makeStore()
        setBudget(store, "restaurants", 50)
        setBudget(store, "leisure", 300)
        for month in 7...9 {
            store.upsert(expense(83, "groceries", on: day(2026, month, 10)))
            store.upsert(expense(90, "restaurants", on: day(2026, month, 10)))
            store.upsert(expense(40, "leisure", on: day(2026, month, 10)))
        }
        let suggestions = Dictionary(uniqueKeysWithValues: store.budgetSuggestions(now: now).map { ($0.id, $0) })
        XCTAssertEqual(suggestions["groceries"]?.reason, .noBudget)
        XCTAssertEqual(suggestions["groceries"]?.suggested, 85)
        XCTAssertEqual(suggestions["restaurants"]?.reason, .tooLow)
        XCTAssertEqual(suggestions["restaurants"]?.suggested, 90)
        XCTAssertEqual(suggestions["leisure"]?.reason, .tooHigh)
        XCTAssertEqual(suggestions["leisure"]?.suggested, 40)

        store.apply(suggestions["groceries"]!)
        XCTAssertEqual(store.category(id: "groceries").monthlyBudget, 85)
    }

    func testOperationAtMidnightOnFirstBelongsToOneMonth() {
        let store = makeStore()
        let midnight = Calendar.current.startOfDay(for: day(2026, 10, 1))
        store.upsert(expense(30, "restaurants", on: midnight))
        XCTAssertEqual(store.transactions(inMonthOf: day(2026, 9, 15)).count, 0)
        XCTAssertEqual(store.transactions(inMonthOf: day(2026, 10, 15)).count, 1)
        XCTAssertEqual(store.spent(in: store.category(id: "restaurants"), month: day(2026, 9, 15)), 0)
    }

    func testRoundedBudget() {
        XCTAssertEqual(BudgetStore.roundedBudget(42.3), 45)
        XCTAssertEqual(BudgetStore.roundedBudget(45), 45)
        XCTAssertEqual(BudgetStore.roundedBudget(101), 110)
        XCTAssertEqual(BudgetStore.roundedBudget(0), 0)
    }

    func testOldCategoriesDecodeWithoutNewFields() throws {
        let json = #"{"id":"x","label":"X","icon":"star","kind":"expense","colorIndex":0,"isHidden":false,"monthlyBudget":20}"#
        let category = try JSONDecoder().decode(Category.self, from: Data(json.utf8))
        XCTAssertNil(category.budgetOverrides)
        XCTAssertNil(category.budgetRollover)
    }
}
