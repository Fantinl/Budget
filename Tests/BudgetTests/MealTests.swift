import XCTest
@testable import Budget

@MainActor
final class MealTests: StoreTestCase {
    // Lundi 5 octobre 2026 → vendredi 16 octobre 2026 (2 semaines ouvrées).
    private let monday = startOfDay(2026, 10, 5)
    private let friday2 = day(2026, 10, 16)

    private func izlyStore(enabled: Bool = true) -> (BudgetStore, Account) {
        let store = makeStore()
        var account = Account.makeIzly(id: "izly", existing: store.accounts, paletteCount: 8)
        account.mealPlan?.startDate = monday
        account.mealPlan?.isEnabled = enabled
        store.upsertAccount(account)
        return (store, account)
    }

    private func meals(_ store: BudgetStore) -> [Transaction] { store.transactions.filter { $0.isAutoMeal == true } }

    func testGeneratesWeekdaysOverTwoWeeks() {
        let (store, _) = izlyStore()
        store.generateDueMeals(now: friday2)
        XCTAssertEqual(meals(store).count, 10)
        XCTAssertTrue(meals(store).allSatisfy { $0.amount == 1 && $0.accountID == "izly" && $0.note == "Repas Crous" })
        XCTAssertEqual(store.account(id: "izly").mealPlan?.lastGeneratedDate, startOfDay(2026, 10, 16))
    }

    func testNoDuplicateOnSecondCall() {
        let (store, _) = izlyStore()
        store.generateDueMeals(now: friday2)
        store.generateDueMeals(now: friday2)
        XCTAssertEqual(meals(store).count, 10)
        store.generateDueMeals(now: day(2026, 10, 19))
        XCTAssertEqual(meals(store).count, 11)
    }

    func testNoMealBeforeStartNorOnWeekend() {
        let (store, _) = izlyStore()
        store.generateDueMeals(now: day(2026, 10, 4)) // dimanche avant le début
        XCTAssertTrue(meals(store).isEmpty)
        store.generateDueMeals(now: day(2026, 10, 11)) // dimanche : 5 repas, aucun le week-end
        XCTAssertEqual(meals(store).count, 5)
        XCTAssertFalse(meals(store).contains { [1, 7].contains(Calendar.current.component(.weekday, from: $0.date)) })
    }

    func testDisabledPlanCreatesNothing() {
        let (store, _) = izlyStore(enabled: false)
        store.generateDueMeals(now: friday2)
        XCTAssertTrue(meals(store).isEmpty)
    }

    func testAddMealsSkipsCountedDays() {
        let (store, account) = izlyStore()
        store.generateDueMeals(now: day(2026, 10, 9)) // 5 repas du 5 au 9
        let added = store.addMeals(to: account, from: monday, to: day(2026, 10, 16), weekdays: [2, 3, 4, 5, 6], price: 1)
        XCTAssertEqual(added, 5)
        XCTAssertEqual(meals(store).count, 10)
    }

    func testRemoveMealsAndUndo() {
        let (store, account) = izlyStore()
        let manager = attachUndoManager(to: store)
        store.generateDueMeals(now: friday2)
        let ids = Set(meals(store).prefix(3).map(\.id))
        inUndoGroup(manager) { XCTAssertEqual(store.removeMeals(ids: ids), 3) }
        XCTAssertEqual(meals(store).count, 7)
        manager.undo()
        XCTAssertEqual(meals(store).count, 10)
        let interval = DateInterval(start: monday, end: day(2026, 10, 17))
        XCTAssertEqual(store.meals(of: account, in: interval).count, 10)
    }

    func testNeedsReviewAfterSevenDaysThenMarked() {
        let (store, account) = izlyStore()
        store.generateDueMeals(now: day(2026, 10, 9))
        XCTAssertNil(store.needsMealReview(now: day(2026, 10, 9)))
        store.generateDueMeals(now: day(2026, 10, 12))
        XCTAssertEqual(store.needsMealReview(now: day(2026, 10, 12))?.id, "izly")
        store.markMealsReviewed(account: account, now: day(2026, 10, 12))
        XCTAssertNil(store.needsMealReview(now: day(2026, 10, 12)))
        XCTAssertNil(store.needsMealReview(now: day(2026, 10, 16)))
    }

    func testReviewAppliesInOneUndo() {
        let (store, account) = izlyStore()
        let manager = attachUndoManager(to: store)
        store.generateDueMeals(now: day(2026, 10, 9))
        let days = store.mealReviewDays(of: store.account(id: "izly"), now: day(2026, 10, 9))
        XCTAssertEqual(days.count, 5)
        let present = Set(days.dropFirst(2))
        inUndoGroup(manager) { store.applyMealReview(account: account, days: days, present: present, now: day(2026, 10, 9)) }
        XCTAssertEqual(meals(store).count, 3)
        XCTAssertNotNil(store.account(id: "izly").mealPlan?.lastReviewDate)
        manager.undo()
        XCTAssertEqual(meals(store).count, 5)
    }

    func testBalanceWithTransferAndMeals() {
        let (store, account) = izlyStore()
        store.createTransfer(from: Account.mainID, to: "izly", amount: 20, date: day(2026, 10, 5), note: "Recharge")
        store.generateDueMeals(now: friday2)
        XCTAssertEqual(store.balance(of: account, asOf: day(2026, 10, 20)), 10)
        XCTAssertEqual(store.mealsRemaining(of: store.account(id: "izly")), 10)
    }

    func testIzlyOperationsHiddenFromOperations() {
        let (store, _) = izlyStore()
        store.createTransfer(from: Account.mainID, to: "izly", amount: 20, date: day(2026, 10, 5), note: "Recharge")
        store.generateDueMeals(now: friday2)
        let visible = store.transactions.filter { !store.isHiddenFromOperations($0) }
        XCTAssertEqual(visible.count, 1) // seule la jambe sortante du compte principal
        XCTAssertEqual(visible.first?.resolvedAccountID, Account.mainID)
        let summary = store.izlySpending(in: store.transactions)
        XCTAssertEqual(summary.count, 10)
        XCTAssertEqual(summary.total, 10)
    }

    /// Un compte Izly enregistré sans plan de repas (version précédente) reçoit le plan par défaut au chargement.
    func testExistingIzlyAccountGetsDefaultMealPlan() throws {
        let store = makeStore()
        var izly = Account(name: "Izly", kind: .izly, colorIndex: 3)
        izly.mealPlan = nil
        store.accounts.append(izly)
        store.saveSettings()
        let reloaded = BudgetStore(directory: store.directory)
        let plan = try XCTUnwrap(reloaded.accounts.first { $0.id == izly.id }?.mealPlan)
        XCTAssertTrue(plan.isEnabled)
        XCTAssertEqual(plan.weekdays, [2, 3, 4, 5, 6])
        XCTAssertTrue(Calendar.current.isDateInToday(plan.startDate))
    }
}
