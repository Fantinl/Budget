import XCTest
@testable import Budget

final class ImportIzlyTests: StoreTestCase {
    private var izly: Account!
    private let today = startOfDay(2026, 10, 12)

    override func setUp() {
        super.setUp()
        izly = Account(name: "Izly", kind: .izly, colorIndex: 0)
    }

    private func importSample(_ store: BudgetStore) {
        let rows = [StatementRow(date: today, label: "CB IZLY SMONEY 12/10", signedAmount: -20),
                    StatementRow(date: today, label: "CARREFOUR", signedAmount: -35),
                    StatementRow(date: today, label: "SALAIRE", signedAmount: 1500)]
        let categorizer = StatementCategorizer(categories: store.categories, transactions: store.transactions)
        let imported = rows.dropFirst().map {
            Transaction(amount: $0.amount, kind: $0.kind, categoryID: categorizer.suggest(label: $0.label, kind: $0.kind), note: $0.label, date: $0.date)
        }
        let recharge = ImportRecharge(amount: 20, date: today, note: rows[0].label, izlyAccountID: izly.id)
        store.addImported(Array(imported), recharges: [recharge], from: Account.mainID)
    }

    func testRechargeLabelDetection() {
        XCTAssertTrue(ImportRecharge.matches(label: "CB IZLY SMONEY 12/10"))
        XCTAssertTrue(ImportRecharge.matches(label: "recharge izly"))
        XCTAssertFalse(ImportRecharge.matches(label: "CARREFOUR"))
    }

    func testRechargeBecomesTransferToIzly() {
        let store = makeStore()
        store.accounts.append(izly)
        importSample(store)
        let legs = store.transactions.filter(\.isTransfer)
        XCTAssertEqual(legs.count, 2)
        XCTAssertEqual(legs[0].transferID, legs[1].transferID)
        XCTAssertEqual(store.transactions.count, 4)
        XCTAssertEqual(store.balance(of: .main), 1500 - 35 - 20)
        XCTAssertEqual(store.balance(of: izly), 20)
        XCTAssertFalse(legs.contains(where: \.isSpending), "une recharge n'est pas une dépense")
    }

    func testReimportIsDetectedAsDuplicate() {
        let store = makeStore()
        store.accounts.append(izly)
        importSample(store)
        let index = store.duplicateIndex()
        let key = BudgetStore.duplicateKey(date: today, kind: .expense, amount: 20, accountID: Account.mainID)
        XCTAssertGreaterThan(index.amounts[key] ?? 0, 0)
        let labelKey = BudgetStore.duplicateLabelKey(date: today, label: "carrefour", accountID: Account.mainID)
        XCTAssertTrue(index.labels.contains(labelKey))
    }

    func testRechargeFromIzlyAccountItselfIsIgnored() {
        let store = makeStore()
        store.accounts.append(izly)
        let recharge = ImportRecharge(amount: 20, date: today, note: "IZLY", izlyAccountID: izly.id)
        store.addImported([], recharges: [recharge], from: izly.id)
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testImportIsOneUndoStep() {
        let store = makeStore()
        store.accounts.append(izly)
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) { importSample(store) }
        manager.undo()
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testCrousIsCategorizedAsRestaurant() {
        let categorizer = StatementCategorizer(categories: Category.defaults, transactions: [])
        XCTAssertEqual(categorizer.suggest(label: "CB CROUS PARIS", kind: .expense), "restaurants")
    }

    func testImportWithoutRechargeKeepsPlainBehaviour() {
        let store = makeStore()
        store.addImported([expense(5, on: today)])
        XCTAssertEqual(store.transactions.count, 1)
        store.addImported([])
        XCTAssertEqual(store.transactions.count, 1)
    }
}
