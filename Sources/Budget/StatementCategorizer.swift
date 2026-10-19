import Foundation

/// Propose une catégorie pour chaque ligne d'un relevé.
struct StatementCategorizer {
    private let categories: [Category]
    /// Opérations existantes : mots-clés du libellé -> catégorie la plus fréquente.
    private var known: [(tokens: Set<String>, categoryID: String)] = []
    private let fallbackIDs: (expense: String, income: String)

    private static let stopWords: Set<String> = [
        "cb", "carte", "prlv", "prelevement", "vir", "virement", "paiement", "achat", "sepa",
        "par", "de", "du", "des", "the", "inst", "sct", "remise", "retrait",
    ]

    /// Mots-clés par catégorie, dans l'ordre de priorité (« uber eats » avant « uber »).
    private static let keywords: [(id: String, kind: TransactionKind, words: [String])] = [
        ("restaurants", .expense, ["restaurant", "resto", "mcdo", "mcdonald", "burger king", "kfc", "deliveroo", "uber eats", "just eat", "brasserie", "pizza", "sushi", "starbucks", "boulangerie", "izly", "crous"]),
        ("groceries", .expense, ["carrefour", "leclerc", "auchan", "lidl", "monoprix", "intermarche", "franprix", "casino", "picard", "aldi", "supermarche", "biocoop", "grand frais"]),
        ("transport", .expense, ["sncf", "ratp", "navigo", "total", "totalenergies", "esso", "uber", "peage", "bp", "blablacar", "vinci autoroutes", "sanef", "autoroute", "parking", "ouigo", "tisseo"]),
        ("housing", .expense, ["loyer", "syndic", "edf", "engie", "foncia"]),
        ("subscriptions", .expense, ["netflix", "spotify", "free", "orange", "sfr", "bouygues", "disney", "canal+", "deezer", "apple.com", "icloud", "youtube", "amazon prime", "sosh", "red by sfr"]),
        ("health", .expense, ["pharmacie", "medecin", "mutuelle", "docteur", "dentiste", "hopital", "kine", "optique", "laboratoire", "doctolib"]),
        ("shopping", .expense, ["amazon", "fnac", "decathlon", "zara", "h&m", "ikea", "cdiscount", "darty", "leroy merlin", "zalando", "boulanger"]),
        ("salary", .income, ["salaire", "virement employeur", "paie"]),
        ("refund", .income, ["remboursement", "rembt", "cpam", "ameli"]),
    ]

    init(categories: [Category], transactions: [Transaction]) {
        self.categories = categories
        fallbackIDs = (BudgetStore.fallbackID(for: .expense), BudgetStore.fallbackID(for: .income))

        // Catégorie la plus fréquente pour chaque libellé distinct (catégories encore existantes seulement).
        var counts: [Set<String>: [String: Int]] = [:]
        for transaction in transactions where !transaction.note.isEmpty {
            guard categories.contains(where: { $0.id == transaction.categoryID }) else { continue }
            let tokens = Self.tokens(transaction.note)
            guard !tokens.isEmpty else { continue }
            counts[tokens, default: [:]][transaction.categoryID, default: 0] += 1
        }
        known = counts.compactMap { tokens, byCategory in
            byCategory.max { $0.value < $1.value }.map { (tokens, $0.key) }
        }
    }

    /// Catégorie proposée pour un libellé et un type d'opération.
    func suggest(label: String, kind: TransactionKind) -> String {
        let tokens = Self.tokens(label)

        // (a) Libellé très proche d'une opération existante du même type.
        var bestMatch: (id: String, score: Double)?
        for entry in known where isValid(entry.categoryID, kind) && !tokens.isEmpty {
            let common = tokens.intersection(entry.tokens).count
            guard common > 0 else { continue }
            let score = Double(common) / Double(tokens.union(entry.tokens).count)
            if score >= 0.7, score > (bestMatch?.score ?? 0) { bestMatch = (entry.categoryID, score) }
        }
        if let bestMatch { return bestMatch.id }

        // (b) Mots-clés courants.
        let words = StatementParser.normalize(label)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "+" && $0 != "." && $0 != "&" })
            .map(String.init)
        let padded = " " + words.joined(separator: " ") + " "
        for group in Self.keywords where group.kind == kind && isValid(group.id, kind) {
            for keyword in group.words {
                if keyword.contains(" ") {
                    if padded.contains(" \(keyword) ") { return group.id }
                } else if keyword.count <= 4 {
                    if words.contains(keyword) { return group.id }
                } else if words.contains(where: { $0.hasPrefix(keyword) }) {
                    return group.id
                }
            }
        }

        // (c) « Autre » du bon type.
        return kind == .expense ? fallbackIDs.expense : fallbackIDs.income
    }

    private func isValid(_ id: String, _ kind: TransactionKind) -> Bool {
        categories.contains { $0.id == id && $0.kind == kind && !$0.isHidden }
    }

    /// Mots significatifs d'un libellé : sans accents, sans chiffres ni mots bancaires génériques.
    private static func tokens(_ text: String) -> Set<String> {
        let words = StatementParser.normalize(text)
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return Set(words)
    }
}
