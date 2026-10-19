import XCTest
@testable import Budget

/// Seuils larges : ils ne détectent qu'une vraie régression, pas les variations d'une machine à l'autre.
final class PerformanceTests: StoreTestCase {
    private let limit: Double = 1.0
    private let now = day(2026, 10, 15)

    private func makeLargeStore() -> BudgetStore {
        let store = makeStore()
        let categories = store.categories(for: .expense).map(\.id)
        let start = Calendar.current.date(byAdding: .year, value: -3, to: now)!
        let span = now.timeIntervalSince(start)
        store.transactions = (0..<5_000).map { i in
            let date = start.addingTimeInterval(span * Double(i) / 5_000)
            return Transaction(amount: Decimal(i % 97) + Decimal(string: "0.5")!, kind: i % 10 == 0 ? .income : .expense,
                               categoryID: categories[i % categories.count], note: "Opération \(i)", date: date)
        }
        return store
    }

    /// Chronomètre un bloc, l'affiche et vérifie le seuil.
    private func timed(_ name: String, _ block: () -> Void) {
        let clock = ContinuousClock()
        let elapsed = clock.measure(block)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        print("PERF \(name): \(String(format: "%.1f", seconds * 1000)) ms")
        XCTAssertLessThan(seconds, limit, "\(name) trop lent : \(seconds) s")
    }

    func testSaveReloadAndQueriesWith5000Transactions() {
        let store = makeLargeStore()
        timed("enregistrement 5000 opérations") { store.saveTransactions() }

        var reloaded: BudgetStore!
        timed("rechargement depuis le disque") { reloaded = makeStore() }
        XCTAssertEqual(reloaded.transactions.count, 5_000)

        var month: [Transaction] = []
        timed("transactions(inMonthOf:)") { month = store.transactions(inMonthOf: now) }
        XCTAssertFalse(month.isEmpty)

        var snapshot: StatsSnapshot!
        timed("StatsSnapshot sur l'année") {
            snapshot = StatsSnapshot(transactions: store.transactions, period: .year, offset: 0,
                                     category: store.category(id:), now: now)
        }
        XCTAssertTrue(snapshot.hasData)

        var forecast: MonthForecast!
        timed("monthForecast()") { forecast = store.monthForecast(now: now) }
        XCTAssertNotNil(forecast.estimatedSpending)
    }

    func testOtherAggregatesWith5000Transactions() {
        let store = makeLargeStore()
        timed("solde du compte") { _ = store.balance(of: .main) }
        timed("export CSV") { _ = CSVExport.data(for: store.transactions, store: store) }
        timed("index des doublons") { _ = store.duplicateIndex() }
        timed("statistiques « Tout »") {
            _ = StatsSnapshot(transactions: store.transactions, period: .all, offset: 0, category: store.category(id:), now: now)
        }
    }

    func testMeasureTransactionsOfMonth() {
        let store = makeLargeStore()
        measure { _ = store.transactions(inMonthOf: now) }
    }
}
