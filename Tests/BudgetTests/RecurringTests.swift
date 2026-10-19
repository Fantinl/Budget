import XCTest
@testable import Budget

final class RecurringTests: StoreTestCase {
    private func monthly(_ name: String = "Loyer", start: Date, end: Date? = nil, frequency: RecurrenceFrequency = .monthly,
                         amount: Decimal = 700, kind: TransactionKind = .expense, account: String? = nil) -> RecurringOperation {
        RecurringOperation(name: name, amount: amount, kind: kind, categoryID: "otherExpense", accountID: account, note: "",
                           frequency: frequency, startDate: start, endDate: end, isActive: true, lastGeneratedDate: nil)
    }

    private func monthDays(_ store: BudgetStore, _ id: UUID) -> [String] {
        store.transactions.filter { $0.recurringID == id }
            .sorted { $0.date < $1.date }
            .map { let c = Calendar.current.dateComponents([.month, .day], from: $0.date); return "\(c.month!)/\(c.day!)" }
    }

    func testEndOfMonthOccurrencesAreClamped() {
        let store = makeStore()
        let rec = monthly(start: startOfDay(2026, 1, 31))
        store.recurringOperations = [rec]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertEqual(monthDays(store, rec.id), ["1/31", "2/28", "3/31", "4/30", "5/31", "6/30", "7/31", "8/31", "9/30"])
    }

    func testLeapYearFebruary() {
        let store = makeStore()
        let rec = monthly(start: startOfDay(2028, 1, 31))
        store.recurringOperations = [rec]
        store.generateDueRecurringOperations(now: startOfDay(2028, 3, 1))
        XCTAssertEqual(monthDays(store, rec.id), ["1/31", "2/29"])
    }

    func testNoDuplicateOnSecondCall() {
        let store = makeStore()
        let rec = monthly(start: startOfDay(2026, 1, 31))
        store.recurringOperations = [rec]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertEqual(store.transactions.count, 9)
    }

    func testDueDateCreatedTheSameDay() {
        let store = makeStore()
        let rec = monthly(start: startOfDay(2026, 1, 31))
        store.recurringOperations = [rec]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 31))
        XCTAssertEqual(store.transactions.count, 10)
    }

    func testNextOccurrence() {
        let store = makeStore()
        let rec = monthly(start: startOfDay(2026, 1, 31))
        store.recurringOperations = [rec]
        XCTAssertEqual(store.nextOccurrence(of: rec, after: startOfDay(2026, 10, 31)), startOfDay(2026, 11, 30))
    }

    func testWeeklyWithEndDate() {
        let store = makeStore()
        let weekly = monthly("Marché", start: startOfDay(2026, 10, 1), end: startOfDay(2026, 10, 15), frequency: .weekly, amount: 20)
        store.recurringOperations = [weekly]
        store.generateDueRecurringOperations(now: startOfDay(2026, 12, 1))
        XCTAssertEqual(monthDays(store, weekly.id), ["10/1", "10/8", "10/15"])
    }

    func testQuarterlyAndYearly() {
        let store = makeStore()
        let quarterly = monthly("Assurance", start: startOfDay(2026, 1, 15), frequency: .quarterly)
        let yearly = monthly("Impôt", start: startOfDay(2024, 9, 20), frequency: .yearly)
        store.recurringOperations = [quarterly, yearly]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertEqual(monthDays(store, quarterly.id), ["1/15", "4/15", "7/15", "10/15"])
        XCTAssertEqual(monthDays(store, yearly.id), ["9/20", "9/20", "9/20"])
    }

    func testInactiveRecurringGeneratesNothing() {
        let store = makeStore()
        var rec = monthly(start: startOfDay(2026, 1, 1))
        rec.isActive = false
        store.recurringOperations = [rec]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testFutureStartGeneratesNothing() {
        let store = makeStore()
        store.recurringOperations = [monthly(start: startOfDay(2026, 12, 1))]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testGeneratedOperationsPersist() {
        let store = makeStore()
        store.recurringOperations = [monthly(start: startOfDay(2026, 8, 1))]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.transactions.count, 3)
        XCTAssertNotNil(reloaded.recurringOperations[0].lastGeneratedDate)
        reloaded.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertEqual(reloaded.transactions.count, 3)
    }

    func testRecurringWithoutAccountUsesDefaultAccount() {
        let store = makeStore()
        let livret = Account(name: "Livret", kind: .livretA, colorIndex: 1)
        store.upsertAccount(livret)
        store.setDefaultAccount(livret)
        let rec = monthly(start: startOfDay(2026, 10, 1))
        store.recurringOperations = [rec]
        store.generateDueRecurringOperations(now: startOfDay(2026, 10, 17))
        XCTAssertEqual(store.transactions.first { $0.recurringID == rec.id }?.accountID, livret.id)
    }
}
