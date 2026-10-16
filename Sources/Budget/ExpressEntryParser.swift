import Foundation

/// Interprétation d'une saisie express (« café 2,5 hier »). Fonction pure : testable sans interface.
struct ExpressEntry: Equatable {
    var amount: Decimal?
    var kind: TransactionKind
    var date: Date
    var label: String
}

enum ExpressEntryParser {
    private static let weekdays: [String: Int] = [   // Calendar : dimanche = 1
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7,
    ]
    private static let incomeWords: Set<String> = [
        "salaire", "paie", "paye", "remboursement", "rembt", "prime", "rembourse", "cpam", "ameli",
    ]
    private static let incomePhrases = ["virement recu"]

    // MARK: Analyse du texte

    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> ExpressEntry {
        let text = collapseOperators(input)
        var tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var date = now
        var amount: Decimal?
        var plusSign = false
        var amountIndex: Int?
        var consumed = Set<Int>()

        // Dates : mots-clés, jj/mm[/aaaa], « le 5 », jour de semaine.
        var i = 0
        var dateFound = false
        while i < tokens.count {
            let word = fold(tokens[i])
            if !dateFound {
                if word == "hier" {
                    date = shift(now, days: -1, calendar); consumed.insert(i); dateFound = true
                } else if word == "avant-hier" || word == "avanthier" {
                    date = shift(now, days: -2, calendar); consumed.insert(i); dateFound = true
                } else if word == "avant", i + 1 < tokens.count, fold(tokens[i + 1]) == "hier" {
                    date = shift(now, days: -2, calendar); consumed.formUnion([i, i + 1]); dateFound = true
                } else if word == "aujourd'hui" || word == "aujourdhui" || word == "auj" {
                    consumed.insert(i); dateFound = true
                } else if let weekday = weekdays[word] {
                    date = lastWeekday(weekday, from: now, calendar); consumed.insert(i); dateFound = true
                } else if let explicit = explicitDate(word, now: now, calendar: calendar) {
                    date = explicit; consumed.insert(i); dateFound = true
                } else if word == "le", i + 1 < tokens.count {
                    let next = fold(tokens[i + 1])
                    if let day = Int(next), (1...31).contains(day) {
                        date = dayOfMonth(day, now: now, calendar); consumed.formUnion([i, i + 1]); dateFound = true
                        i += 1
                    } else if let explicit = explicitDate(next, now: now, calendar: calendar) {
                        date = explicit; consumed.formUnion([i, i + 1]); dateFound = true
                        i += 1
                    }
                }
            }
            i += 1
        }

        // Montant : premier jeton calculable (nombre ou calcul), « + » en tête = revenu.
        for (index, token) in tokens.enumerated() where !consumed.contains(index) && amount == nil {
            var candidate = token
            var plus = false
            if candidate.hasPrefix("+") { plus = true; candidate.removeFirst() }
            guard candidate.contains(where: { $0.isASCII && $0.isNumber }),
                  candidate.allSatisfy({ "0123456789.,+-−×x*/÷()€".contains($0) }),
                  let value = AmountExpression.evaluate(candidate), value > 0 else { continue }
            amount = value
            plusSign = plus
            amountIndex = index
        }
        if let amountIndex { consumed.insert(amountIndex) }

        tokens = tokens.enumerated().filter { !consumed.contains($0.offset) }.map(\.element)
        let label = capitalizeFirst(tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces))

        let words = Set(fold(label).split(whereSeparator: { !$0.isLetter }).map(String.init))
        let folded = fold(label)
        let isIncome = plusSign || !words.isDisjoint(with: incomeWords) || incomePhrases.contains { folded.contains($0) }

        return ExpressEntry(amount: amount, kind: isIncome ? .income : .expense, date: date, label: label)
    }

    // MARK: Catégorie

    /// Catégorie devinée : (a) ajout rapide ou nom de catégorie, (b) mots-clés, (c) libellé passé identique, (d) « Autre ».
    static func guessCategoryID(label: String, kind: TransactionKind, categories: [Category],
                                quickExpenses: [QuickExpense], transactions: [Transaction]) -> String {
        let valid = categories.filter { $0.kind == kind && !$0.isHidden }
        let fallback = BudgetStore.fallbackID(for: kind)
        let normalized = fold(label)
        guard !normalized.isEmpty else { return fallback }
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        // (a) Nom d'un ajout rapide, puis libellé de catégorie.
        for quick in quickExpenses where quick.kind == kind && valid.contains(where: { $0.id == quick.categoryID }) {
            if matches(fold(quick.name), words: words, normalized: normalized) { return quick.categoryID }
        }
        for category in valid where matches(fold(category.label), words: words, normalized: normalized) {
            return category.id
        }

        // (b) Mots-clés de StatementCategorizer (sans l'historique, traité en (c)).
        let byKeyword = StatementCategorizer(categories: categories, transactions: []).suggest(label: label, kind: kind)
        if byKeyword != fallback { return byKeyword }

        // (c) Opération passée au libellé identique.
        let identical = transactions
            .filter { t in t.kind == kind && fold(t.note) == normalized && valid.contains { c in c.id == t.categoryID } }
            .max { $0.date < $1.date }
        if let identical { return identical.categoryID }

        // (d) « Autre » du type.
        return fallback
    }

    private static func matches(_ name: String, words: [String], normalized: String) -> Bool {
        guard !name.isEmpty else { return false }
        if normalized == name { return true }
        let nameWords = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if nameWords.count > 1 { return " \(normalized) ".contains(" \(name) ") }
        guard let single = nameWords.first else { return false }
        return words.contains { $0 == single || (single.count >= 4 && $0.count >= 4 && ($0.hasPrefix(single) || single.hasPrefix($0))) }
    }

    // MARK: Dates

    private static func shift(_ date: Date, days: Int, _ calendar: Calendar) -> Date {
        noon(calendar.date(byAdding: .day, value: days, to: date) ?? date, calendar)
    }

    /// Midi : évite les décalages de fuseau ou d'heure d'été.
    private static func noon(_ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    /// Jour de semaine le plus proche dans le passé (aujourd'hui compris).
    private static func lastWeekday(_ weekday: Int, from now: Date, _ calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: now)
        let back = (current - weekday + 7) % 7
        return back == 0 ? now : shift(now, days: -back, calendar)
    }

    /// « Le 25 » : ce mois-ci, ou le mois précédent si le jour est dans le futur (ou inexistant).
    private static func dayOfMonth(_ day: Int, now: Date, _ calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        var month = calendar.dateInterval(of: .month, for: now)?.start ?? today
        for _ in 0..<13 {
            let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<29
            if day < range.upperBound,
               let candidate = calendar.date(byAdding: .day, value: day - 1, to: month),
               candidate <= today {
                return candidate == today ? now : noon(candidate, calendar)
            }
            month = calendar.date(byAdding: .month, value: -1, to: month) ?? month
        }
        return now
    }

    /// jj/mm ou jj/mm/aaaa (séparateurs / . -). Jamais dans le futur.
    private static func explicitDate(_ word: String, now: Date, calendar: Calendar) -> Date? {
        let parts = word.split(omittingEmptySubsequences: false, whereSeparator: { "/.".contains($0) }).map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.count == 3 || word.contains("/"),
              let day = Int(parts[0]), let month = Int(parts[1]), (1...31).contains(day), (1...12).contains(month)
        else { return nil }
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: now)
        var year = currentYear
        if parts.count == 3, let given = Int(parts[2]) {
            guard parts[2].count == 2 || parts[2].count == 4 else { return nil }
            year = parts[2].count == 2 ? 2000 + given : given
        }
        func make(_ y: Int) -> Date? {
            let comps = DateComponents(year: y, month: month, day: day, hour: 12)
            guard let date = calendar.date(from: comps),
                  calendar.component(.day, from: date) == day else { return nil }
            return date
        }
        guard var date = make(year) else { return nil }
        if date > now && parts.count == 2, let previous = make(year - 1) { date = previous }
        if calendar.startOfDay(for: date) > today { return now }
        return calendar.isDate(date, inSameDayAs: now) ? now : date
    }

    // MARK: Texte

    /// Retire les espaces autour des opérateurs entre deux chiffres (« 12 + 8,5 » devient « 12+8,5 »).
    private static func collapseOperators(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?<=[\d)€])\s*([+×*÷/])\s*(?=[\d(])"#, with: "$1", options: .regularExpression)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased().replacingOccurrences(of: "’", with: "'")
    }

    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
