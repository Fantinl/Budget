import XCTest
@testable import Budget

final class CSVExportTests: StoreTestCase {
    private func csv(_ store: BudgetStore) -> [String] {
        let text = String(decoding: CSVExport.data(for: store.transactions, store: store), as: UTF8.self)
        return text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    func testHeaderAndBOM() {
        let store = makeStore()
        let data = CSVExport.data(for: [], store: store)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF])
        XCTAssertEqual(csv(store).first?.hasSuffix("Date;Type;Catégorie;Compte;Description;Montant"), true)
    }

    func testSignedFrenchAmounts() {
        let store = makeStore()
        store.upsert(expense(700, "housing", note: "Loyer", on: day(2026, 10, 5)))
        store.upsert(income(1234.5, "salary", note: "Salaire", on: day(2026, 10, 28)))
        let lines = csv(store)
        XCTAssertEqual(lines[1], "05/10/2026;Dépense;Logement;Compte courant;Loyer;-700,00")
        XCTAssertEqual(lines[2], "28/10/2026;Revenu;Salaire;Compte courant;Salaire;1234,50")
    }

    func testEscapingOfSpecialCharacters() {
        XCTAssertEqual(CSVExport.escape("simple"), "simple")
        XCTAssertEqual(CSVExport.escape("a;b"), "\"a;b\"")
        XCTAssertEqual(CSVExport.escape("dit \"oui\""), "\"dit \"\"oui\"\"\"")
        XCTAssertEqual(CSVExport.escape("l1\nl2"), "\"l1\nl2\"")
    }

    func testTransferShownAsTransfer() {
        let store = makeStore()
        let livret = Account(name: "Livret", kind: .livretA, colorIndex: 1)
        store.upsertAccount(livret)
        store.createTransfer(from: Account.mainID, to: livret.id, amount: 50, date: day(2026, 10, 1), note: "")
        let lines = csv(store)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.dropFirst().allSatisfy { $0.contains(";Virement;Virement;") })
    }

    func testRowsAreSortedByDate() {
        let store = makeStore()
        store.upsert(expense(1, note: "B", on: day(2026, 10, 9)))
        store.upsert(expense(1, note: "A", on: day(2026, 10, 2)))
        let lines = csv(store)
        XCTAssertTrue(lines[1].hasPrefix("02/10/2026"))
        XCTAssertTrue(lines[2].hasPrefix("09/10/2026"))
    }

    func testPeriodIntervalsAndFileNames() {
        let now = day(2026, 10, 17)
        let from = day(2026, 3, 10), to = day(2026, 1, 5)   // inversés exprès
        XCTAssertEqual(CSVPeriod.thisMonth.interval(from: from, to: to, now: now)?.start, startOfDay(2026, 10, 1))
        XCTAssertEqual(CSVPeriod.lastMonth.interval(from: from, to: to, now: now)?.start, startOfDay(2026, 9, 1))
        XCTAssertEqual(CSVPeriod.thisYear.interval(from: from, to: to, now: now)?.end, startOfDay(2027, 1, 1))
        XCTAssertNil(CSVPeriod.all.interval(from: from, to: to, now: now))
        let custom = CSVPeriod.custom.interval(from: from, to: to, now: now)
        XCTAssertEqual(custom?.start, startOfDay(2026, 1, 5))
        XCTAssertEqual(custom?.end, startOfDay(2026, 3, 11))
        XCTAssertEqual(CSVPeriod.thisMonth.fileName(from: from, to: to, now: now), "Budget-2026-10.csv")
        XCTAssertEqual(CSVPeriod.lastMonth.fileName(from: from, to: to, now: now), "Budget-2026-09.csv")
        XCTAssertEqual(CSVPeriod.thisYear.fileName(from: from, to: to, now: now), "Budget-2026.csv")
        XCTAssertEqual(CSVPeriod.all.fileName(from: from, to: to, now: now), "Budget-tout.csv")
        XCTAssertEqual(CSVPeriod.custom.fileName(from: from, to: to, now: now), "Budget-2026-01-05_2026-03-10.csv")
    }
}
