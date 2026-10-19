import XCTest
@testable import Budget

final class StoreMigrationTests: StoreTestCase {
    func testOldFilesLoadWithoutError() throws {
        // Ancien settings.json (sans comptes ni récurrentes) et ancien transactions.json (sans accountID).
        try write(#"{"categories":[{"id":"groceries","label":"Courses","icon":"cart.fill","kind":"expense","colorIndex":0,"isHidden":false}],"quickExpenses":[]}"#,
                  as: "settings.json")
        try write(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","amount":12.5,"kind":"expense","category":"groceries","note":"Pain","date":"2026-10-01T10:00:00Z"}]"#,
                  as: "transactions.json")
        let store = makeStore()
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.transactions[0].resolvedAccountID, Account.mainID)
        XCTAssertEqual(store.accounts.map(\.id), ["main"])
        XCTAssertEqual(store.defaultAccountID, Account.mainID)
    }

    func testFallbackCategoriesAreRecreated() throws {
        try write(#"{"categories":[{"id":"groceries","label":"Courses","icon":"cart.fill","kind":"expense","colorIndex":0,"isHidden":false}],"quickExpenses":[]}"#,
                  as: "settings.json")
        let store = makeStore()
        XCTAssertTrue(store.categories.contains { $0.id == "otherExpense" })
        XCTAssertTrue(store.categories.contains { $0.id == "otherIncome" })
    }

    func testOldAccountsDecodeAndUnknownKindFallsBackToChecking() throws {
        let json = #"[{"id":"x","name":"Ma carte","kind":"card","colorIndex":1,"initialBalance":10,"isArchived":false},{"id":"y","name":"?","kind":"futur","colorIndex":0,"initialBalance":0,"isArchived":false}]"#
        let accounts = try BudgetStore.decoder.decode([Account].self, from: Data(json.utf8))
        XCTAssertEqual(accounts[0].kind, .card)
        XCTAssertNil(accounts[0].bank)
        XCTAssertEqual(accounts[1].kind, .checking)
    }

    func testCorruptFileIsKeptAsideAndReported() throws {
        try write("pas du json", as: "transactions.json")
        let store = makeStore()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.transactions.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("transactions.illisible-") })
        XCTAssertFalse(names.contains("transactions.json"))
    }

    func testSaveAndReloadRoundTrip() {
        let store = makeStore()
        store.upsert(expense(12.34, "groceries", note: "Pain", on: day(2026, 3, 4)))
        store.upsertAccount(Account(name: "Livret", kind: .livretA, colorIndex: 1, initialBalance: 50, bank: "Banque"))
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.transactions, store.transactions)
        XCTAssertEqual(reloaded.accounts, store.accounts)
        XCTAssertEqual(reloaded.transactions[0].amount, Decimal(string: "12.34"))
    }

    func testStoreNeverUsesDefaultDirectoryInTests() {
        XCTAssertNotEqual(makeStore().directory, BudgetStore.defaultDirectory)
    }
}
