import XCTest
@testable import Budget

final class StatsDrillDownTests: XCTestCase {
    func testCategoryTransactionsInPeriodNewestFirst() {
        var transfer = expense(30, "restaurants", on: day(2026, 10, 9))
        transfer.transferID = UUID()
        let all = [
            expense(10, "restaurants", on: day(2026, 10, 3)),
            expense(20, "restaurants", on: day(2026, 10, 12)),
            expense(5, "groceries", on: day(2026, 10, 5)),
            expense(99, "restaurants", on: day(2026, 9, 30)),
            expense(98, "restaurants", on: day(2026, 11, 1)),
            income(50, "restaurants", on: day(2026, 10, 6)),
            transfer,
        ]
        let result = StatsSnapshot.transactions(in: "restaurants", from: all,
                                                start: startOfDay(2026, 10, 1), end: startOfDay(2026, 11, 1))
        XCTAssertEqual(result.map(\.amount), [20, 10])
    }

    func testAccountFilterIsAppliedByCaller() {
        let all = [expense(10, "restaurants", on: day(2026, 10, 3), account: "a"),
                   expense(20, "restaurants", on: day(2026, 10, 4))]
        let filtered = all.filter { $0.resolvedAccountID == "a" }
        let result = StatsSnapshot.transactions(in: "restaurants", from: filtered,
                                                start: startOfDay(2026, 10, 1), end: startOfDay(2026, 11, 1))
        XCTAssertEqual(result.count, 1)
    }
}
