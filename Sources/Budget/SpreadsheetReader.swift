import Foundation

// Lecture des tableurs (.xlsx, .xls « HTML ») en grille de texte. Logique pure, sans SwiftUI.

enum SpreadsheetReader {
    // MARK: Dates et nombres Excel

    /// Jours depuis le 30/12/1899 -> « jj/mm/aaaa » (la fraction d'heure est ignorée).
    static func dateText(fromSerial serial: Double) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let date = Date(timeIntervalSince1970: (floor(serial) - 25569) * 86400)
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 1, c.month ?? 1, c.year ?? 1970)
    }

    /// Nombre Excel (point décimal, notation scientifique possible) -> texte arrondi au centime.
    static func numberText(_ raw: String) -> String {
        guard var value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    // MARK: xlsx

    static func xlsxGrid(data: Data) throws -> [[String]] {
        #if os(macOS)
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("budget-xlsx-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let zip = dir.appendingPathComponent("file.xlsx")
        try data.write(to: zip)
        let out = dir.appendingPathComponent("x")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", "-o", zip.path, "xl/*", "-d", out.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw StatementError.excelUnreadable }
        process.waitUntilExit()

        func file(_ path: String) -> Data? { try? Data(contentsOf: out.appendingPathComponent(path)) }

        let shared = file("xl/sharedStrings.xml").map { parse(SharedStringsParser(), $0).strings } ?? []
        let dateStyles = file("xl/styles.xml").map { parse(StylesParser(), $0).dateStyleIndexes() } ?? []

        // Feuilles dans l'ordre du classeur.
        var sheetPaths: [String] = []
        if let workbook = file("xl/workbook.xml") {
            let sheets = parse(WorkbookParser(), workbook).sheetIDs
            var targets: [String: String] = [:]
            if let rels = file("xl/_rels/workbook.xml.rels") { targets = parse(RelsParser(), rels).targets }
            for id in sheets {
                guard var target = targets[id] else { continue }
                if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
                sheetPaths.append(target)
            }
        }
        if sheetPaths.isEmpty { sheetPaths = ["xl/worksheets/sheet1.xml"] }

        var best: [[String]] = []
        for path in sheetPaths {
            guard let sheet = file(path) else { continue }
            let grid = parse(SheetParser(shared: shared, dateStyles: Set(dateStyles)), sheet).grid
            let count = grid.filter { $0.contains { !$0.isEmpty } }.count
            if count > 0 { return grid }   // première feuille non vide
            if count > best.count { best = grid }
        }
        if best.isEmpty && sheetPaths.allSatisfy({ file($0) == nil }) { throw StatementError.excelUnreadable }
        return best
        #else
        throw StatementError.excelUnsupported
        #endif
    }

    private static func parse<P: XMLParserDelegate>(_ delegate: P, _ data: Data) -> P {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate
    }

    // MARK: Parseurs XML

    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var inT = false
        private var phoneticDepth = 0

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "si": current = ""
            case "t": inT = true
            case "rPh": phoneticDepth += 1
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inT && phoneticDepth == 0 { current += string }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "t": inT = false
            case "rPh": phoneticDepth -= 1
            case "si": strings.append(current)
            default: break
            }
        }
    }

    private final class StylesParser: NSObject, XMLParserDelegate {
        var customFormats: [Int: String] = [:]
        var xfFormatIDs: [Int] = []
        private var inCellXfs = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "numFmt":
                if let id = attributes["numFmtId"].flatMap({ Int($0) }), let code = attributes["formatCode"] { customFormats[id] = code }
            case "cellXfs": inCellXfs = true
            case "xf" where inCellXfs: xfFormatIDs.append(attributes["numFmtId"].flatMap { Int($0) } ?? 0)
            default: break
            }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "cellXfs" { inCellXfs = false }
        }

        func dateStyleIndexes() -> [Int] {
            xfFormatIDs.enumerated().compactMap { index, id in Self.isDateFormat(id, custom: customFormats[id]) ? index : nil }
        }

        static func isDateFormat(_ id: Int, custom: String?) -> Bool {
            if (14...22).contains(id) || (45...47).contains(id) { return true }
            guard var code = custom else { return false }
            // On retire les textes entre guillemets, les crochets ([$€-40C], [Red]) et les caractères échappés.
            for pattern in ["\"[^\"]*\"", "\\[[^\\]]*\\]", "\\\\."] {
                code = code.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            }
            return code.lowercased().contains { $0 == "d" || $0 == "m" || $0 == "y" }
        }
    }

    private final class WorkbookParser: NSObject, XMLParserDelegate {
        var sheetIDs: [String] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            guard name == "sheet" else { return }
            if let key = attributes.keys.first(where: { $0 == "id" || $0.hasSuffix(":id") }), let id = attributes[key] { sheetIDs.append(id) }
        }
    }

    private final class RelsParser: NSObject, XMLParserDelegate {
        var targets: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            guard name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] else { return }
            targets[id] = target
        }
    }

    private final class SheetParser: NSObject, XMLParserDelegate {
        let shared: [String]
        let dateStyles: Set<Int>
        var grid: [[String]] = []

        private var rowIndex = -1
        private var column = 0
        private var type = ""
        private var style = 0
        private var text = ""
        private var capturing = false
        private var inInline = false

        init(shared: [String], dateStyles: Set<Int>) {
            self.shared = shared
            self.dateStyles = dateStyles
        }

        private func place(_ value: String) {
            while grid.count <= rowIndex { grid.append([]) }
            while grid[rowIndex].count <= column { grid[rowIndex].append("") }
            grid[rowIndex][column] = value
        }

        /// « C5 » -> (colonne 2, ligne 4).
        private func position(_ ref: String) -> (column: Int, row: Int)? {
            var col = 0
            var digits = ""
            for ch in ref.uppercased() {
                if let ascii = ch.asciiValue, ascii >= 65, ascii <= 90, digits.isEmpty { col = col * 26 + Int(ascii) - 64 }
                else if ch.isNumber { digits.append(ch) }
            }
            guard col > 0 else { return nil }
            return (col - 1, (Int(digits) ?? 0) - 1)
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            switch name {
            case "row":
                if let r = attributes["r"].flatMap({ Int($0) }), r > 0 { rowIndex = r - 1 } else { rowIndex += 1 }
                column = -1
            case "c":
                column += 1
                if let pos = attributes["r"].flatMap(position) {
                    column = pos.column
                    if pos.row >= 0 { rowIndex = pos.row }
                }
                if rowIndex < 0 { rowIndex = 0 }
                type = attributes["t"] ?? ""
                style = attributes["s"].flatMap { Int($0) } ?? 0
                text = ""
            case "v": capturing = true
            case "is": inInline = true
            case "t" where inInline: capturing = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { text += string }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": capturing = false
            case "is": inInline = false
            case "c":
                let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
                var value = ""
                switch type {
                case "s": value = Int(raw).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? ""
                case "inlineStr", "str", "e": value = text
                case "b": value = raw == "1" ? "VRAI" : "FAUX"
                default:
                    if raw.isEmpty { value = "" }
                    else if dateStyles.contains(style), let serial = Double(raw) { value = SpreadsheetReader.dateText(fromSerial: serial) }
                    else { value = SpreadsheetReader.numberText(raw) }
                }
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { place(value) }
            default: break
            }
        }
    }

    // MARK: HTML (faux .xls)

    static func htmlGrid(_ html: String) -> [[String]] {
        let options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
        guard let rowRegex = try? NSRegularExpression(pattern: "<tr\\b[^>]*>(.*?)(?=</tr\\s*>|<tr\\b|</table|$)", options: options),
              let cellRegex = try? NSRegularExpression(pattern: "<t[dh]\\b[^>]*>(.*?)(?=</t[dh]\\s*>|<t[dh]\\b|</tr|$)", options: options)
        else { return [] }

        func captures(_ regex: NSRegularExpression, in text: String) -> [String] {
            let ns = text as NSString
            return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
        }

        var grid: [[String]] = []
        for row in captures(rowRegex, in: html) {
            let cells = captures(cellRegex, in: row).map(cleanHTML)
            if cells.contains(where: { !$0.isEmpty }) { grid.append(cells) }
        }
        return grid
    }

    /// Retire les balises, décode les entités, normalise les espaces.
    private static func cleanHTML(_ fragment: String) -> String {
        var s = fragment.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        return s.split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" }).joined(separator: " ")
    }

    private static let entities: [String: String] = [
        "nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "agrave": "à", "acirc": "â", "auml": "ä",
        "ccedil": "ç", "icirc": "î", "iuml": "ï", "ocirc": "ô", "ouml": "ö", "ugrave": "ù", "ucirc": "û", "uuml": "ü",
        "Eacute": "É", "Egrave": "È", "Ecirc": "Ê", "Agrave": "À", "Acirc": "Â", "Ccedil": "Ç", "Icirc": "Î",
        "Ocirc": "Ô", "Ugrave": "Ù", "oelig": "œ", "OElig": "Œ", "euro": "€", "laquo": "«", "raquo": "»",
        "deg": "°", "rsquo": "’", "lsquo": "‘", "hellip": "…", "ndash": "–", "mdash": "—", "middot": "·",
    ]

    /// Décode en un seul passage (pas de double décodage de « &amp;lt; »).
    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&"), let regex = try? NSRegularExpression(pattern: "&(#[xX]?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);") else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let name = ns.substring(with: match.range(at: 1))
            var replacement: String?
            if name.hasPrefix("#") {
                let body = name.dropFirst()
                let code = body.first == "x" || body.first == "X" ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
                replacement = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = entities[name]
            }
            result += replacement ?? ns.substring(with: match.range)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
