import XCTest
@testable import Budget

/// Le compte Izly n'est pas proposé dans les sélecteurs ; il se recharge depuis sa page.
@MainActor
final class IzlyAccountTests: StoreTestCase {
    private func storeWithIzly() -> (BudgetStore, Account) {
        let store = makeStore()
        let izly = Account(name: "Izly", kind: .izly, colorIndex: 2, initialBalance: 5)
        store.upsertAccount(izly)
        return (store, izly)
    }

    func testSelectableAccountsExcludeIzly() {
        let (store, izly) = storeWithIzly()
        XCTAssertFalse(store.selectableAccounts.contains { $0.id == izly.id })
        XCTAssertTrue(store.activeAccounts.contains { $0.id == izly.id })
        XCTAssertTrue(store.selectableAccounts.contains { $0.id == Account.mainID })
    }

    func testIzlyDefaultAccountFallsBackToMain() {
        let (store, izly) = storeWithIzly()
        store.setDefaultAccount(izly)
        XCTAssertEqual(store.defaultAccount.id, Account.mainID)
    }

    func testTopUpTransferUpdatesBothBalances() {
        let (store, izly) = storeWithIzly()
        let main = store.account(id: Account.mainID)
        let mainBefore = store.balance(of: main)
        store.createTransfer(from: main.id, to: izly.id, amount: 20, date: .now, note: "")
        XCTAssertEqual(store.balance(of: main), mainBefore - 20)
        XCTAssertEqual(store.balance(of: izly), 25)
    }

    func testIzlyStaysInNetWorth() {
        let (store, izly) = storeWithIzly()
        let before = store.totalBalance()
        store.createTransfer(from: Account.mainID, to: izly.id, amount: 10, date: .now, note: "")
        XCTAssertEqual(store.totalBalance(), before)
        XCTAssertTrue(store.activeAccounts.contains { $0.id == izly.id })
    }
}
