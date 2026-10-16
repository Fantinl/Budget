import Foundation

// Lecture d'un relevé bancaire (CSV ou OFX). Logique pure, sans SwiftUI.

/// Ligne lisible d'un relevé. Le montant est signé : négatif = dépense, positif = revenu.
struct StatementRow: Hashable {
    var date: Date
    var label: String
    var signedAmount: Decimal

    var kind: TransactionKind { signedAmount < 0 ? .expense : .income }
    var amount: Decimal { signedAmount < 0 ? -signedAmount : signedAmount }
}

/// Numéros de colonnes (à partir de 0) choisis pour lire un CSV.
struct StatementColumns: Hashable {
    var date: Int?
    var label: Int?
    var amount: Int?
    var debit: Int?
    var credit: Int?

    /// Vrai si le montant vient de deux colonnes débit / crédit.
    var isSplit: Bool { amount == nil && (debit != nil || credit != nil) }
}

/// Tableau brut d'un CSV, une fois l'en-tête repéré.
struct StatementTable {
    var headers: [String]
    var rows: [[String]]
    var columns: StatementColumns
}

struct StatementResult {
    var rows: [StatementRow]
    var skipped: Int
}

enum StatementContent {
    case table(StatementTable)
    case rows(StatementResult)   // OFX : déjà lu
}

enum StatementError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "Impossible de lire ce fichier."
        case .empty: "Aucune opération trouvée dans ce fichier."
        }
    }
}

enum StatementParser {
    // MARK: Point d'entrée

    static func parse(data: Data) throws -> StatementContent {
        let text = decode(data)
        guard !text.isEmpty else { throw StatementError.unreadable }
        if text.range(of: "<STMTTRN>", options: .caseInsensitive) != nil {
            let result = parseOFX(text)
            guard !result.rows.isEmpty else { throw StatementError.empty }
            return .rows(result)
        }
        guard let table = parseCSV(text) else { throw StatementError.empty }
        return .table(table)
    }

    // MARK: Encodage

    /// UTF-8 d'abord, sinon Windows-1252, sinon Latin 1 (qui accepte tous les octets).
    static func decode(_ data: Data) -> String {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) { return text }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: CSV

    static func parseCSV(_ text: String) -> StatementTable? {
        var best: (table: StatementTable, delimiter: Character)?
        var fallback: (records: [[String]], score: Int)?

        for delimiter: Character in [";", "\t", ","] {
            let records = tokenize(text, delimiter: delimiter)
            if let index = headerIndex(in: records) {
                let headers = records[index]
                let rows = records[(index + 1)...].filter { row in row.contains { !$0.isEmpty } }
                let table = StatementTable(headers: headers, rows: Array(rows), columns: detectColumns(headers))
                // Plus il y a de colonnes reconnues, mieux c'est ; à égalité, le premier séparateur gagne.
                if best == nil { best = (table, delimiter) }
            }
            let score = records.prefix(5).reduce(0) { $0 + $1.count }
            if fallback == nil || score > fallback!.score { fallback = (records, score) }
        }
        if let best { return best.table }

        // Aucun en-tête reconnu : première ligne = en-têtes, l'utilisateur choisira les colonnes.
        guard let records = fallback?.records, let first = records.first, first.count > 1 else { return nil }
        let rows = records.dropFirst().filter { row in row.contains { !$0.isEmpty } }
        return StatementTable(headers: first, rows: Array(rows), columns: StatementColumns())
    }

    /// Découpe le texte en enregistrements (guillemets, guillemets doublés, retours à la ligne dans un champ).
    static func tokenize(_ text: String, delimiter: Character) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending = iterator.next()

        func endRecord() {
            record.append(field.trimmingCharacters(in: .whitespaces))
            field = ""
            if record.contains(where: { !$0.isEmpty }) { records.append(record) }
            record = []
        }

        while let c = pending {
            pending = iterator.next()
            if inQuotes {
                if c == "\"" {
                    if pending == "\"" { field.append("\""); pending = iterator.next() } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                record.append(field.trimmingCharacters(in: .whitespaces))
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                endRecord()
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !record.isEmpty { endRecord() }
        return records
    }

    /// Première ligne (parmi les 40 premières) qui ressemble à des en-têtes : date + montant (ou débit/crédit).
    private static func headerIndex(in records: [[String]]) -> Int? {
        for (index, record) in records.prefix(40).enumerated() where record.count >= 2 {
            let columns = detectColumns(record)
            guard let date = columns.date else { continue }
            let others = [columns.amount, columns.debit, columns.credit].compactMap { $0 }
            if others.contains(where: { $0 != date }) { return index }
        }
        return nil
    }

    // MARK: Détection des colonnes

    /// Minuscules, sans accents, espaces réduits.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" })
            .joined(separator: " ")
    }

    static func detectColumns(_ headers: [String]) -> StatementColumns {
        let names = headers.map(normalize)

        func best(_ score: (String) -> Int) -> Int? {
            var result: (index: Int, score: Int)?
            for (index, name) in names.enumerated() {
                let value = score(name)
                if value > 0, value > (result?.score ?? 0) { result = (index, value) }
            }
            return result?.index
        }

        let date = best { name in
            guard name.contains("date") else { return 0 }
            if name == "date" { return 100 }
            if name.contains("operation") || name.contains("dateop") { return 90 }
            if name.contains("comptab") { return 80 }
            if name.contains("valeur") || name.contains("dateval") { return 10 }
            return 50
        }
        let label = best { name in
            guard !name.contains("date"), !name.contains("categor") else { return 0 }
            if name.hasPrefix("libelle") || name == "label" { return 100 }
            if name.contains("description") || name.contains("intitule") { return 90 }
            if name.contains("libelle") { return 80 }
            if name.contains("operation") || name.contains("motif") || name.contains("objet") { return 60 }
            if name.contains("detail") || name.contains("beneficiaire") || name.contains("tiers") { return 40 }
            if name == "nom" || name == "name" || name == "memo" { return 30 }
            return 0
        }
        let amount = best { name in
            if name == "montant" || name == "amount" { return 100 }
            if name.hasPrefix("montant") && !name.contains("devise") { return 60 }
            return 0
        }
        let debit = best { name in
            name.contains("debit") ? (name.hasPrefix("debit") ? 100 : 60) : 0
        }
        let credit = best { name in
            name.contains("credit") ? (name.hasPrefix("credit") ? 100 : 60) : 0
        }
        return StatementColumns(date: date, label: label, amount: amount, debit: debit, credit: credit)
    }

    // MARK: Lecture des lignes

    /// Transforme le tableau en opérations avec les colonnes choisies ; les lignes illisibles sont comptées.
    static func rows(from table: StatementTable, columns: StatementColumns) -> StatementResult {
        var rows: [StatementRow] = []
        var skipped = 0

        func cell(_ row: [String], _ index: Int?) -> String {
            guard let index, row.indices.contains(index) else { return "" }
            return row[index]
        }

        for row in table.rows {
            guard columns.date != nil, let date = parseDate(cell(row, columns.date)) else { skipped += 1; continue }
            let label = cleanLabel(cell(row, columns.label))

            var signed: Decimal?
            if let amountIndex = columns.amount {
                signed = parseAmount(cell(row, amountIndex))
            } else {
                let debit = parseAmount(cell(row, columns.debit))
                let credit = parseAmount(cell(row, columns.credit))
                if let debit, debit != 0 { signed = -abs(debit) }
                else if let credit, credit != 0 { signed = abs(credit) }
            }
            guard let signed, signed != 0 else { skipped += 1; continue }
            rows.append(StatementRow(date: date, label: label.isEmpty ? "Sans libellé" : label, signedAmount: signed))
        }
        return StatementResult(rows: rows, skipped: skipped)
    }

    /// Espaces multiples réduits, extrémités nettoyées.
    static func cleanLabel(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" }).joined(separator: " ")
    }

    // MARK: Dates

    /// jj/mm/aaaa, jj/mm/aa, jj-mm-aaaa, jj.mm.aaaa, aaaa-mm-jj, aaaammjj (heure ignorée).
    static func parseDate(_ text: String) -> Date? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end = s.firstIndex(where: { $0 == " " || $0 == "T" }) { s = String(s[..<end]) }
        guard !s.isEmpty else { return nil }
        // OFX : « 20240315120000[+1:CET] » -> on garde les chiffres du début.
        let leadingDigits = s.prefix(while: \.isNumber)
        if leadingDigits.count >= 8 { s = String(leadingDigits) }

        var numbers: [Int] = []
        var lengths: [Int] = []
        if s.allSatisfy(\.isNumber), s.count >= 8 {
            let digits = Array(s)
            numbers = [Int(String(digits[0..<4])), Int(String(digits[4..<6])), Int(String(digits[6..<8]))].compactMap { $0 }
            lengths = [4, 2, 2]
        } else {
            let parts = s.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
            guard parts.count == 3 else { return nil }
            for part in parts {
                guard let value = Int(part) else { return nil }
                numbers.append(value)
                lengths.append(part.count)
            }
        }
        guard numbers.count == 3 else { return nil }

        var (day, month, year) = lengths[0] == 4 ? (numbers[2], numbers[1], numbers[0]) : (numbers[0], numbers[1], numbers[2])
        if year < 100 { year += 2000 }
        guard (1...31).contains(day), (1...12).contains(month), (1990...2100).contains(year) else { return nil }

        var components = DateComponents(year: year, month: month, day: day, hour: 12)
        components.calendar = Calendar.current
        guard let date = Calendar.current.date(from: components),
              Calendar.current.component(.day, from: date) == day else { return nil }
        return date
    }

    // MARK: Montants

    /// « -1 234,56 », « 1234.56 », « 1 234,56 € », « 12,50- », « (12,50) ».
    static func parseAmount(_ text: String) -> Decimal? {
        var s = text.uppercased()
        for junk in ["EUR", "€", "\u{00A0}", "\u{202F}", " ", "+", "'"] { s = s.replacingOccurrences(of: junk, with: "") }
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasSuffix("-") { negative = true; s.removeLast() }
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "," || $0 == "." }) else { return nil }

        // Le dernier séparateur est la virgule décimale ; les autres sont des milliers.
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        var decimalIndex: String.Index?
        switch (lastComma, lastDot) {
        case let (c?, d?): decimalIndex = max(c, d)
        case let (c?, nil): decimalIndex = s.filter { $0 == "," }.count == 1 ? c : nil
        case let (nil, d?): decimalIndex = s.filter { $0 == "." }.count == 1 ? d : nil
        default: break
        }
        var normalized = ""
        for index in s.indices {
            let c = s[index]
            if c == "," || c == "." {
                if index == decimalIndex { normalized.append(".") }
            } else {
                normalized.append(c)
            }
        }
        guard var value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if negative { value = -value }
        return value
    }

    // MARK: OFX

    static func parseOFX(_ text: String) -> StatementResult {
        var rows: [StatementRow] = []
        var skipped = 0
        let blocks = text.components(separatedBy: "<STMTTRN>").dropFirst()
        for block in blocks {
            let date = ofxValue("DTPOSTED", in: block).flatMap(parseDate)
            let amount = ofxValue("TRNAMT", in: block).flatMap(parseAmount)
            guard let date, let amount, amount != 0 else { skipped += 1; continue }
            let name = ofxValue("NAME", in: block) ?? ""
            let memo = ofxValue("MEMO", in: block) ?? ""
            var label = name.isEmpty ? memo : name
            if !name.isEmpty, !memo.isEmpty, !name.localizedCaseInsensitiveContains(memo), !memo.localizedCaseInsensitiveContains(name) {
                label += " " + memo
            }
            label = cleanLabel(unescapeXML(label))
            rows.append(StatementRow(date: date, label: label.isEmpty ? "Sans libellé" : label, signedAmount: amount))
        }
        return StatementResult(rows: rows, skipped: skipped)
    }

    /// Valeur d'une balise OFX (avec ou sans balise fermante).
    private static func ofxValue(_ tag: String, in block: String) -> String? {
        guard let start = block.range(of: "<\(tag)>", options: .caseInsensitive) else { return nil }
        let rest = block[start.upperBound...]
        let end = rest.firstIndex(where: { $0 == "<" || $0 == "\n" || $0 == "\r" }) ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func unescapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}
