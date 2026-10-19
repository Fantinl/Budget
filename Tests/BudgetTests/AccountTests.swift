import XCTest
@testable import Budget

final class AccountTests: StoreTestCase {
    func testDefaultAccountPersistsAndFallsBackWhenArchived() {
        let store = makeStore()
        let livret = Account(name: "Livret", kind: .livretA, colorIndex: 1)
        store.upsertAccount(livret)
        store.setDefaultAccount(livret)
        XCTAssertEqual(store.defaultAccount.id, livret.id)
        XCTAssertEqual(makeStore().defaultAccountID, livret.id)
        store.archiveAccount(livret)
        XCTAssertEqual(store.defaultAccount.id, Account.mainID)
    }

    func testMainAccountCannotBeArchivedNorDeleted() {
        let store = makeStore()
        store.archiveAccount(.main)
        XCTAssertFalse(store.account(id: Account.mainID).isArchived)
        XCTAssertFalse(store.deleteAccount(.main))
        var archived = Account.main
        archived.isArchived = true
        store.upsertAccount(archived)
        XCTAssertFalse(store.account(id: Account.mainID).isArchived)
    }

    func testDeleteAccountOnlyWhenUnused() {
        let store = makeStore()
        let livret = Account(name: "Livret", kind: .livretA, colorIndex: 1)
        store.upsertAccount(livret)
        store.upsert(income(10, on: day(2026, 10, 1), account: livret.id))
        XCTAssertFalse(store.deleteAccount(livret))
        store.delete(store.transactions[0])
        XCTAssertTrue(store.deleteAccount(livret))
        XCTAssertFalse(store.accounts.contains { $0.id == livret.id })
    }

    func testBalanceAndTotal() {
        let store = makeStore()
        let livret = Account(name: "Livret", kind: .livretA, colorIndex: 1, initialBalance: 100)
        store.upsertAccount(livret)
        store.upsert(income(50, on: day(2026, 1, 10)))
        store.upsert(expense(20, on: day(2026, 1, 20)))
        store.upsert(income(5, on: day(2026, 1, 20), account: livret.id))
        XCTAssertEqual(store.balance(of: .main), 30)
        XCTAssertEqual(store.balance(of: livret), 105)
        XCTAssertEqual(store.balance(of: .main, asOf: day(2026, 1, 15)), 50)
        XCTAssertEqual(store.totalBalance(), 135)
        store.archiveAccount(livret)
        XCTAssertEqual(store.totalBalance(), 30)
    }

    func testMarketValueAndGain() {
        let store = makeStore()
        let pea = Account(name: "PEA", kind: .pea, colorIndex: 3, initialBalance: 1000, marketValue: 1200)
        store.upsertAccount(pea)
        XCTAssertEqual(store.value(of: pea), 1200)
        XCTAssertEqual(store.gain(of: pea), 200)
        let noValuation = Account(name: "AV", kind: .assuranceVie, colorIndex: 3, initialBalance: 500)
        XCTAssertEqual(store.value(of: noValuation), 500)
        XCTAssertNil(store.gain(of: noValuation))
        let checking = Account(name: "C", kind: .checking, colorIndex: 0, initialBalance: 10, marketValue: 999)
        XCTAssertEqual(store.value(of: checking), 10)
        XCTAssertNil(store.gain(of: checking))
    }

    func testBanksAreSortedAndDeduplicated() {
        let store = makeStore()
        store.upsertAccount(Account(name: "A", kind: .livretA, colorIndex: 0, bank: "Boursorama"))
        store.upsertAccount(Account(name: "B", kind: .ldds, colorIndex: 0, bank: "Boursorama"))
        store.upsertAccount(Account(name: "C", kind: .pea, colorIndex: 0, bank: "Crédit Agricole"))
        XCTAssertEqual(store.banks, ["Boursorama", "Crédit Agricole"])
        XCTAssertEqual(Account.main.bankLabel, "Sans banque")
    }

    // MARK: Taux réglementés (table embarquée, sans réseau)

    func testRegulatedRateUsedWhenAutomatic() {
        let store = makeStore()
        let livretA = Account(name: "LA", kind: .livretA, colorIndex: 0, interestRate: 9)
        XCTAssertTrue(livretA.usesAutoRate)
        XCTAssertEqual(store.effectiveRate(for: livretA), Decimal(string: "1.7"))
        let lep = Account(name: "LEP", kind: .lep, colorIndex: 0)
        XCTAssertEqual(store.effectiveRate(for: lep), Decimal(string: "2.5"))
    }

    func testManualRateWhenAutoDisabled() {
        let store = makeStore()
        let livret = Account(name: "LA", kind: .livretA, colorIndex: 0, interestRate: 3, autoRate: false)
        XCTAssertFalse(livret.usesAutoRate)
        XCTAssertEqual(store.effectiveRate(for: livret), 3)
    }

    func testNonRegulatedAccountKeepsEnteredRate() {
        let store = makeStore()
        let compte = Account(name: "CSL", kind: .savings, colorIndex: 0, interestRate: Decimal(string: "2.1"))
        XCTAssertFalse(compte.kind.hasRegulatedRate)
        XCTAssertNil(store.regulatedRate(for: compte))
        XCTAssertEqual(store.effectiveRate(for: compte), Decimal(string: "2.1"))
    }

    func testPELRateDependsOnOpeningDate() {
        let store = makeStore()
        func rate(_ opening: Date?) -> Decimal? {
            store.effectiveRate(for: Account(name: "PEL", kind: .pel, colorIndex: 0, openingDate: opening))
        }
        XCTAssertEqual(rate(day(2016, 3, 1)), Decimal(string: "1.5"))
        XCTAssertEqual(rate(day(2020, 6, 1)), 1)
        XCTAssertEqual(rate(day(2024, 6, 1)), Decimal(string: "2.25"))
        XCTAssertEqual(rate(day(2026, 3, 1)), 2)
        XCTAssertNil(rate(nil))
        XCTAssertNil(rate(day(2010, 1, 1)))
    }

    func testLivretJeuneRateIsAMinimum() {
        let store = makeStore()
        let regulated = store.regulatedRate(for: Account(name: "LJ", kind: .livretJeune, colorIndex: 0))
        XCTAssertEqual(regulated?.isMinimum, true)
    }

    func testEmbeddedTableMatchesRatesJSON() throws {
        // La copie embarquée doit rester identique à rates.json à la racine du dépôt.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "rates.json"))
        let file = try JSONDecoder().decode(RateTable.self, from: data)
        let embedded = RateTable.embedded
        // Source et notes sont purement informatives : on compare les taux et leurs dates.
        XCTAssertEqual(file.version, embedded.version)
        XCTAssertEqual(file.updatedAt, embedded.updatedAt)
        XCTAssertEqual(file.rates.mapValues { [String($0.rate), $0.since] }, embedded.rates.mapValues { [String($0.rate), $0.since] })
        XCTAssertEqual(file.pel, embedded.pel)
    }

    func testAccountKindFamiliesAndCeilings() {
        XCTAssertEqual(AccountKind.livretA.family, .savings)
        XCTAssertEqual(AccountKind.pea.family, .investment)
        XCTAssertEqual(AccountKind.izly.family, .other)
        XCTAssertEqual(AccountKind.livretA.ceiling, 22_950)
        XCTAssertNil(AccountKind.checking.ceiling)
        XCTAssertTrue(AccountKind.assuranceVie.hasMarketValue)
        XCTAssertFalse(AccountKind.livretA.hasMarketValue)
    }
}
