import XCTest
@testable import Budget

final class TransferTests: StoreTestCase {
    private var livret: Account!

    override func setUp() {
        super.setUp()
        livret = Account(name: "Livret", kind: .livretA, colorIndex: 1)
    }

    private func storeWithLivret() -> BudgetStore {
        let store = makeStore()
        store.upsertAccount(livret)
        return store
    }

    func testTransferMovesMoneyBetweenAccounts() throws {
        let store = storeWithLivret()
        let id = try XCTUnwrap(store.createTransfer(from: Account.mainID, to: livret.id, amount: 100, date: day(2026, 10, 1), note: ""))
        let legs = try XCTUnwrap(store.transferLegs(id: id))
        XCTAssertEqual(legs.out.kind, .expense)
        XCTAssertEqual(legs.in.kind, .income)
        XCTAssertEqual(legs.out.note, BudgetStore.defaultTransferNote)
        XCTAssertEqual(store.balance(of: .main), -100)
        XCTAssertEqual(store.balance(of: livret), 100)
        XCTAssertEqual(store.counterpartAccount(of: legs.out)?.id, livret.id)
        XCTAssertEqual(store.counterpartAccount(of: legs.in)?.id, Account.mainID)
    }

    func testTransferIsNotSpendingNorIncome() {
        let store = storeWithLivret()
        store.createTransfer(from: Account.mainID, to: livret.id, amount: 100, date: day(2026, 10, 1), note: "")
        let month = store.transactions(inMonthOf: day(2026, 10, 1))
        XCTAssertEqual(month.filter(\.isSpending).count, 0)
        XCTAssertEqual(month.filter(\.isEarning).count, 0)
        let snapshot = StatsSnapshot(transactions: store.transactions, period: .month, offset: 0,
                                     category: store.category(id:), now: day(2026, 10, 15))
        XCTAssertEqual(snapshot.expenses, 0)
        XCTAssertEqual(snapshot.income, 0)
        XCTAssertEqual(store.monthForecast(now: day(2026, 10, 15)).current, 0)
    }

    func testInvalidTransfersAreRefused() {
        let store = storeWithLivret()
        XCTAssertNil(store.createTransfer(from: livret.id, to: livret.id, amount: 5, date: day(2026, 10, 1), note: ""))
        XCTAssertNil(store.createTransfer(from: Account.mainID, to: livret.id, amount: 0, date: day(2026, 10, 1), note: ""))
        XCTAssertNil(store.createTransfer(from: Account.mainID, to: livret.id, amount: -3, date: day(2026, 10, 1), note: ""))
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testDeletingOneLegDeletesTheWholeTransfer() throws {
        let store = storeWithLivret()
        let id = try XCTUnwrap(store.createTransfer(from: Account.mainID, to: livret.id, amount: 100, date: day(2026, 10, 1), note: ""))
        let leg = try XCTUnwrap(store.transactions.first { $0.transferID == id })
        XCTAssertEqual(store.deleteTransactions(ids: [leg.id]), 2)
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testUpdateTransfer() throws {
        let store = storeWithLivret()
        let id = try XCTUnwrap(store.createTransfer(from: Account.mainID, to: livret.id, amount: 100, date: day(2026, 10, 1), note: ""))
        store.updateTransfer(id: id, from: livret.id, to: Account.mainID, amount: 40, date: day(2026, 10, 3), note: " Retour ")
        let legs = try XCTUnwrap(store.transferLegs(id: id))
        XCTAssertEqual(legs.out.resolvedAccountID, livret.id)
        XCTAssertEqual(legs.in.resolvedAccountID, Account.mainID)
        XCTAssertEqual(legs.out.amount, 40)
        XCTAssertEqual(legs.in.note, "Retour")
        XCTAssertEqual(store.balance(of: .main), 40)
    }

    func testBulkEditIgnoresTransfers() throws {
        let store = storeWithLivret()
        let id = try XCTUnwrap(store.createTransfer(from: Account.mainID, to: livret.id, amount: 100, date: day(2026, 10, 1), note: ""))
        let ids = Set(store.transactions.filter { $0.transferID == id }.map(\.id))
        XCTAssertEqual(store.updateTransactions(ids: ids) { $0.categoryID = "leisure" }, 0)
        XCTAssertTrue(store.duplicateTransactions(ids: ids).isEmpty)
    }
}
