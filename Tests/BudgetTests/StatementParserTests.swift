import XCTest
@testable import Budget

final class StatementParserTests: XCTestCase {
    private func parseRows(_ data: Data) throws -> (rows: [StatementRow], skipped: Int, table: StatementTable?) {
        switch try StatementParser.parse(data: data) {
        case .table(let table):
            let result = StatementParser.rows(from: table, columns: table.columns)
            return (result.rows, result.skipped, table)
        case .rows(let result):
            return (result.rows, result.skipped, nil)
        }
    }

    private func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    // MARK: CSV

    func testSplitDebitCreditLatin1WithPreamble() throws {
        let text = "Compte;12345678901\nSolde;1 234,56\n\nDate;Libellé;Débit euros;Crédit euros;\n15/03/2024;PAIEMENT CB CARREFOUR  MARKET;12,50;;\n16/03/2024;VIREMENT SALAIRE;;1 800,00;\n17/03/24;\"PRLV \"\"FREE\"\" MOBILE\";19,99;;\nTotal;;;;\n"
        let result = try parseRows(text.data(using: .isoLatin1)!)
        XCTAssertEqual(result.table?.columns.isSplit, true)
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows.map { ymd($0.date) }, ["2024-03-15", "2024-03-16", "2024-03-17"])
        XCTAssertEqual(result.rows.map(\.signedAmount), [-12.5, 1800, Decimal(string: "-19.99")!])
        XCTAssertEqual(result.rows[0].label, "PAIEMENT CB CARREFOUR MARKET")
        XCTAssertEqual(result.rows[2].label, "PRLV \"FREE\" MOBILE")
        XCTAssertEqual(result.rows[1].kind, .income)
        XCTAssertEqual(result.skipped, 1, "la ligne « Total » est ignorée")
    }

    func testSignedAmountColumnWindows1252() throws {
        let text = "Date operation;Libelle operation;Montant\n2024-03-01;LOYER MARS;-750,00\n01/03/2024;REMBOURSEMENT CPAM;+23,40\n;;\nfoo;bar;baz\n"
        let result = try parseRows(text.data(using: .windowsCP1252)!)
        XCTAssertEqual(result.table?.columns.isSplit, false)
        XCTAssertEqual(result.rows.map(\.signedAmount), [-750, Decimal(string: "23.4")!])
        XCTAssertEqual(result.rows.map { ymd($0.date) }, ["2024-03-01", "2024-03-01"])
        XCTAssertEqual(result.skipped, 1)
    }

    func testBoursoramaStyleWithEuroSign() throws {
        let text = "dateOp;dateVal;label;category;categoryParent;supplierFound;amount;comment;accountNum;accountLabel;accountbalance\n2024-03-05;2024-03-05;\"CB Netflix\";Loisirs;Loisirs;netflix;-13,49 €;;0001;CC;100\n"
        let result = try parseRows(Data(text.utf8))
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].label, "CB Netflix")
        XCTAssertEqual(result.rows[0].signedAmount, Decimal(string: "-13.49")!)
    }

    func testCommaDelimitedEnglishNumbers() throws {
        let text = "Date,Description,Amount\n03/04/2024,\"Coffee, shop\",\"-1,234.50\"\n04/04/2024,Uber,-12.5\n"
        let result = try parseRows(Data(text.utf8))
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].label, "Coffee, shop")
        XCTAssertEqual(result.rows.map(\.signedAmount), [Decimal(string: "-1234.5")!, Decimal(string: "-12.5")!])
    }

    func testUTF8BOMIsStripped() throws {
        let text = "Date;Libellé;Montant\n15/10/2026;Café;-3,20\n"
        let result = try parseRows(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))
        XCTAssertEqual(result.table?.headers.first, "Date")
        XCTAssertEqual(result.rows.count, 1)
    }

    func testEmptyAndUnreadableFiles() {
        XCTAssertThrowsError(try StatementParser.parse(data: Data()))
        // Un CSV sans date ni montant reconnaissables ne produit aucune opération.
        let rows = try? parseRows(Data("a,b,c\n1,2,3\n".utf8))
        XCTAssertEqual(rows?.rows.count ?? 0, 0)
    }

    // MARK: OFX

    func testOFX() throws {
        let ofx = "OFXHEADER:100\n<OFX><STMTTRN>\n<TRNTYPE>DEBIT\n<DTPOSTED>20240315120000[+1:CET]\n<TRNAMT>-45.30\n<NAME>AUCHAN\n<MEMO>CB 1234\n</STMTTRN></OFX>"
        let result = try parseRows(Data(ofx.utf8))
        XCTAssertNil(result.table)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(ymd(result.rows[0].date), "2024-03-15")
        XCTAssertEqual(result.rows[0].signedAmount, Decimal(string: "-45.3")!)
        XCTAssertTrue(result.rows[0].label.contains("AUCHAN"))
    }

    func testOFXWithXMLEntitiesAndTwoTransactions() throws {
        let ofx = "<OFX><STMTTRN><DTPOSTED>20240102<TRNAMT>10.00<NAME>A &amp; B</STMTTRN><STMTTRN><DTPOSTED>20240103<TRNAMT>-2.00<NAME>C</STMTTRN></OFX>"
        let result = try parseRows(Data(ofx.utf8))
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertTrue(result.rows[0].label.contains("A & B"))
        XCTAssertEqual(result.rows[1].kind, .expense)
    }

    // MARK: Montants et dates

    func testParseAmount() {
        XCTAssertEqual(StatementParser.parseAmount("1 234,56 €"), Decimal(string: "1234.56"))
        XCTAssertEqual(StatementParser.parseAmount("1.234.567"), 1_234_567)
        XCTAssertEqual(StatementParser.parseAmount("12,50-"), Decimal(string: "-12.5"))
        XCTAssertEqual(StatementParser.parseAmount("-1,234.50"), Decimal(string: "-1234.5"))
        XCTAssertEqual(StatementParser.parseAmount("+23,40"), Decimal(string: "23.4"))
        XCTAssertEqual(StatementParser.parseAmount("12"), 12)
        XCTAssertNil(StatementParser.parseAmount("abc"))
        XCTAssertNil(StatementParser.parseAmount(""))
    }

    func testParseDateFormats() {
        XCTAssertEqual(StatementParser.parseDate("15/03/2024").map(ymd), "2024-03-15")
        XCTAssertEqual(StatementParser.parseDate("15/03/24").map(ymd), "2024-03-15")
        XCTAssertEqual(StatementParser.parseDate("2024-03-15").map(ymd), "2024-03-15")
        XCTAssertEqual(StatementParser.parseDate("15.03.2024").map(ymd), "2024-03-15")
        XCTAssertNil(StatementParser.parseDate("pas une date"))
        XCTAssertNil(StatementParser.parseDate("31/02/2024"))
    }

    func testNormalizeRemovesAccentsAndCase() {
        XCTAssertEqual(StatementParser.normalize("Crédit  Agricole"), StatementParser.normalize("credit agricole"))
    }

    func testCleanLabelCollapsesSpaces() {
        XCTAssertEqual(StatementParser.cleanLabel("  CB   CARREFOUR \n MARKET "), "CB CARREFOUR MARKET")
    }

    func testColumnDetection() {
        let split = StatementParser.detectColumns(["Date", "Libellé", "Débit", "Crédit"])
        XCTAssertEqual(split.date, 0); XCTAssertEqual(split.label, 1)
        XCTAssertEqual(split.debit, 2); XCTAssertEqual(split.credit, 3)
        XCTAssertNil(split.amount)
        let signed = StatementParser.detectColumns(["Date", "Libellé", "Montant"])
        XCTAssertEqual(signed.amount, 2)
    }

    func testTokenizeHandlesQuotesAndEmbeddedNewlines() {
        let records = StatementParser.tokenize("a;\"b;c\";d\n\"x\ny\";\"q\"\"r\";z\n", delimiter: ";")
        XCTAssertEqual(records[0], ["a", "b;c", "d"])
        XCTAssertEqual(records[1], ["x\ny", "q\"r", "z"])
    }
}
