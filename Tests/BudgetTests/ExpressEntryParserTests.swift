import XCTest
@testable import Budget

final class ExpressEntryParserTests: XCTestCase {
    /// Mercredi 14 octobre 2026, 10 h : date de référence fixe.
    private let now = day(2026, 10, 14, hour: 10)
    private let cal = Calendar.current

    private func parse(_ text: String) -> ExpressEntry { ExpressEntryParser.parse(text, now: now) }

    private func ymd(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func testSimpleExpense() {
        let e = parse("café 2,5")
        XCTAssertEqual(e.amount, Decimal(string: "2.5"))
        XCTAssertEqual(e.kind, .expense)
        XCTAssertEqual(e.label, "Café")
        XCTAssertEqual(e.date, now)
    }

    func testYesterday() {
        let e = parse("essence 60 hier")
        XCTAssertEqual(e.amount, 60)
        XCTAssertEqual(e.label, "Essence")
        XCTAssertEqual(ymd(e.date), "2026-10-13")
    }

    func testDayBeforeYesterday() {
        XCTAssertEqual(ymd(parse("pain 1 avant-hier").date), "2026-10-12")
        XCTAssertEqual(ymd(parse("pain 1 avant hier").date), "2026-10-12")
    }

    func testPlusSignMeansIncome() {
        let e = parse("+1800 salaire")
        XCTAssertEqual(e.amount, 1800)
        XCTAssertEqual(e.kind, .income)
        XCTAssertEqual(e.label, "Salaire")
    }

    func testIncomeKeywordWithoutPlus() {
        XCTAssertEqual(parse("remboursement 23,40 cpam").kind, .income)
        XCTAssertEqual(parse("salaire 1500").kind, .income)
        XCTAssertEqual(parse("virement reçu 50").kind, .income)
        XCTAssertEqual(parse("courses 50").kind, .expense)
    }

    func testDayOfMonth() {
        let e = parse("loyer 700 le 5")
        XCTAssertEqual(e.amount, 700)
        XCTAssertEqual(e.label, "Loyer")
        XCTAssertEqual(ymd(e.date), "2026-10-05")
    }

    func testFutureDayOfMonthMeansPreviousMonth() {
        XCTAssertEqual(ymd(parse("loyer 700 le 25").date), "2026-09-25")
        // Le 31 n'existe pas en septembre : on remonte jusqu'à août.
        XCTAssertEqual(ymd(parse("truc 5 le 31").date), "2026-08-31")
    }

    func testToday() {
        XCTAssertEqual(parse("café 2 le 14").date, now)
        XCTAssertEqual(parse("café 2 aujourd'hui").date, now)
    }

    func testCalculatedAmount() {
        let e = parse("12+8,5 déjeuner")
        XCTAssertEqual(e.amount, Decimal(string: "20.5"))
        XCTAssertEqual(e.label, "Déjeuner")
        XCTAssertEqual(parse("12 + 8,5 déjeuner").amount, Decimal(string: "20.5"))
        XCTAssertEqual(parse("3x4,2 cafés").amount, Decimal(string: "12.6"))
    }

    func testExplicitDates() {
        XCTAssertEqual(ymd(parse("resto 30 03/10").date), "2026-10-03")
        XCTAssertEqual(ymd(parse("resto 30 03/10/2025").date), "2025-10-03")
        XCTAssertEqual(ymd(parse("resto 30 3/10/25").date), "2025-10-03")
        XCTAssertEqual(ymd(parse("resto 30 le 03/10").date), "2026-10-03")
    }

    func testFutureExplicitDate() {
        XCTAssertEqual(ymd(parse("resto 30 20/12").date), "2025-12-20", "jj/mm futur sans année → année précédente")
        XCTAssertEqual(parse("resto 30 20/12/2030").date, now, "date explicite future → aujourd'hui")
    }

    func testWeekdayGoesBackToMostRecent() {
        XCTAssertEqual(ymd(parse("pizza 12 lundi").date), "2026-10-12")
        XCTAssertEqual(ymd(parse("pizza 12 vendredi").date), "2026-10-09")
        XCTAssertEqual(parse("pizza 12 mercredi").date, now)
    }

    func testMissingAmount() {
        let e = parse("café")
        XCTAssertNil(e.amount)
        XCTAssertEqual(e.label, "Café")
    }

    func testZeroAmountIgnored() {
        XCTAssertNil(parse("café 0").amount)
    }

    func testCategoryGuessing() {
        let categories = Category.defaults
        let quick = [QuickExpense(name: "Café", amount: 2.5, categoryID: "restaurants")]
        func guess(_ label: String, _ kind: TransactionKind = .expense, history: [Transaction] = []) -> String {
            ExpressEntryParser.guessCategoryID(label: label, kind: kind, categories: categories, quickExpenses: quick, transactions: history)
        }
        XCTAssertEqual(guess("Café"), "restaurants")
        XCTAssertEqual(guess("Santé"), "health", "nom de catégorie")
        XCTAssertEqual(guess(""), "otherExpense")
        XCTAssertEqual(guess("zzz inconnu"), "otherExpense")
        XCTAssertEqual(guess("zzz inconnu", .income), "otherIncome")
        let past = Transaction(amount: 5, kind: .expense, categoryID: "leisure", note: "Bowling du coin", date: now)
        XCTAssertEqual(guess("bowling du coin", history: [past]), "leisure", "libellé identique déjà classé")
    }
}
