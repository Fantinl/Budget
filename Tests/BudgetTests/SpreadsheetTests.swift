import XCTest
@testable import Budget

/// Les .xlsx sont fabriqués ici (zip de XML minimal) avec /usr/bin/zip, dans un dossier temporaire.
final class SpreadsheetTests: StoreTestCase {
    private static let ns = #"xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main""#
    private let contentTypes = #"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>"#
    private let workbook = #"<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Vide" sheetId="1" r:id="rId1"/><sheet name="Releve" sheetId="2" r:id="rId2"/></sheets></workbook>"#
    private let rels = #"<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="x" Target="worksheets/sheet2.xml"/></Relationships>"#
    private let styles = #"<?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="dd\/mm\/yyyy"/></numFmts><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs></styleSheet>"#

    /// Construit un classeur : première feuille vide, deuxième feuille = `sheet`.
    private func makeXLSX(sheet: String, sharedStrings: String) throws -> Data {
        let root = dir.appending(path: "xlsx-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appending(path: "xl/worksheets"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "xl/_rels"), withIntermediateDirectories: true)
        func put(_ text: String, _ path: String) throws { try text.write(to: root.appending(path: path), atomically: true, encoding: .utf8) }
        try put(contentTypes, "[Content_Types].xml")
        try put(workbook, "xl/workbook.xml")
        try put(rels, "xl/_rels/workbook.xml.rels")
        try put(styles, "xl/styles.xml")
        try put("<worksheet \(Self.ns)><sheetData/></worksheet>", "xl/worksheets/sheet1.xml")
        try put(sheet, "xl/worksheets/sheet2.xml")
        try put(sharedStrings, "xl/sharedStrings.xml")

        let output = dir.appending(path: "\(UUID().uuidString).xlsx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", "-X", output.path, "[Content_Types].xml", "xl"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "zip a échoué")
        return try Data(contentsOf: output)
    }

    private func rows(_ data: Data) throws -> (table: StatementTable, rows: [StatementRow], skipped: Int) {
        guard case .table(let table) = try StatementParser.parse(data: data) else {
            XCTFail("tableau attendu"); throw StatementError.empty
        }
        let result = StatementParser.rows(from: table, columns: table.columns)
        return (table, result.rows, result.skipped)
    }

    private func ymd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    func testXlsxDebitCreditWithPreambleAndStyledDates() throws {
        let sst = "<sst \(Self.ns)><si><t>Compte courant n°123</t></si><si><t>Solde au 01/10/2026</t></si><si><t>Date</t></si><si><t>Libellé</t></si><si><t>Débit</t></si><si><t>Crédit</t></si><si><r><t>CB </t></r><r><rPr><b/></rPr><t>CARREFOUR</t></r></si><si><t>VIR SALAIRE</t></si></sst>"
        let sheet = """
        <worksheet \(Self.ns)><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c></row>
        <row r="2"><c r="A2" t="s"><v>1</v></c></row>
        <row r="4"><c r="A4" t="s"><v>2</v></c><c r="B4" t="s"><v>3</v></c><c r="C4" t="s"><v>4</v></c><c r="D4" t="s"><v>5</v></c></row>
        <row r="5"><c r="A5" s="1"><v>46310</v></c><c r="B5" t="s"><v>6</v></c><c r="C5"><v>12.3</v></c></row>
        <row r="6"><c r="A6" s="2"><v>46311.5</v></c><c r="B6" t="inlineStr"><is><t>PRLV EDF</t></is></c><c r="C6"><v>1.2E2</v></c></row>
        <row r="7"><c r="A7" s="1"><v>46312</v></c><c r="B7" t="s"><v>7</v></c><c r="D7"><v>1234.5600000000002</v></c></row>
        </sheetData></worksheet>
        """
        let result = try rows(try makeXLSX(sheet: sheet, sharedStrings: sst))
        XCTAssertEqual(result.table.headers, ["Date", "Libellé", "Débit", "Crédit"])
        XCTAssertEqual(result.rows.count, 3)
        // 46310 = 15/10/2026 (numéro de série Excel).
        XCTAssertEqual(result.rows.map { ymd($0.date) }, ["2026-10-15", "2026-10-16", "2026-10-17"])
        XCTAssertEqual(result.rows.map(\.label), ["CB CARREFOUR", "PRLV EDF", "VIR SALAIRE"])
        XCTAssertEqual(result.rows.map(\.signedAmount), [Decimal(string: "-12.3")!, -120, Decimal(string: "1234.56")!])
    }

    func testXlsxSignedAmountAndTextDates() throws {
        let sst = "<sst \(Self.ns)><si><t>Date</t></si><si><t>Libellé</t></si><si><t>Montant</t></si><si><t>15/10/2026</t></si><si><t>RESTO</t></si></sst>"
        let sheet = """
        <worksheet \(Self.ns)><sheetData>
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>
        <row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c><c r="C2"><v>-23.9</v></c></row>
        <row r="3"><c r="A3"><v>46310</v></c><c r="B3" t="str"><v>SANS STYLE</v></c><c r="C3"><v>5</v></c></row>
        </sheetData></worksheet>
        """
        let result = try rows(try makeXLSX(sheet: sheet, sharedStrings: sst))
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows.map { ymd($0.date) }, ["2026-10-15", "2026-10-15"], "date sans style → nombre de série converti")
        XCTAssertEqual(result.rows.map(\.signedAmount), [Decimal(string: "-23.9")!, 5])
        XCTAssertEqual(result.rows[1].label, "SANS STYLE")
    }

    func testSerialDateHelpers() {
        XCTAssertEqual(SpreadsheetReader.dateText(fromSerial: 46310), "15/10/2026")
        XCTAssertEqual(SpreadsheetReader.dateText(fromSerial: 46311.5), "16/10/2026")
        XCTAssertEqual(SpreadsheetReader.numberText("1.2E2"), "120")
        XCTAssertEqual(SpreadsheetReader.numberText("1234.5600000000002"), "1234.56")
    }

    func testCorruptXlsxThrows() {
        let fake = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 50)
        XCTAssertThrowsError(try StatementParser.parse(data: fake))
    }

    // MARK: .xls

    func testXlsExportedAsHTML() throws {
        let html = #"<html><body><table><tr><th>Date</th><th>Libell&eacute;</th><th>Montant</th></tr><tr><td>15/10/2026</td><td>CAF&nbsp;ALLOC &amp; co&#233;</td><td>1&nbsp;234,50</td></tr><tr><td>16/10/2026</td><td>Caf&eacute;</td><td>-3,20</td></tr></table></body></html>"#
        let result = try rows(Data(html.utf8))
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].label, "CAF ALLOC & coé")
        XCTAssertEqual(result.rows[0].signedAmount, Decimal(string: "1234.5")!)
        XCTAssertEqual(result.rows[1].label, "Café")
        XCTAssertEqual(result.rows[1].signedAmount, Decimal(string: "-3.2")!)
    }

    func testBinaryXlsGivesExplicitError() {
        let ole = Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) + Data(repeating: 0, count: 100)
        XCTAssertThrowsError(try StatementParser.parse(data: ole)) { error in
            XCTAssertEqual(error as? StatementError, .legacyExcel)
        }
    }

    // MARK: Non-régression CSV

    func testCSVStillReadAfterSpreadsheetSupport() throws {
        let csv = "Relevé\nDate;Libellé;Débit;Crédit\n15/10/2026;\"CB \"\"X\"\" ;1\";12,50;\n16/10/2026;SALAIRE;;1 500,00\nfoo;bar;;\n"
        let result = try rows(Data(csv.utf8))
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].label, "CB \"X\" ;1")
        XCTAssertEqual(result.rows.map(\.signedAmount), [Decimal(string: "-12.5")!, 1500])
        XCTAssertEqual(result.skipped, 1)
    }
}
