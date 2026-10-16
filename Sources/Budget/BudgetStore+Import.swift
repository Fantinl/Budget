import Foundation

extension BudgetStore {
    /// Ajoute les opérations importées en une seule fois (une seule sauvegarde).
    func addImported(_ imported: [Transaction]) {
        registerUndo("Importer le relevé")
        guard !imported.isEmpty else { return }
        transactions.append(contentsOf: imported)
        saveTransactions()
    }

    /// Clés « jour|type|montant|compte » des opérations existantes, avec leur nombre.
    func duplicateIndex() -> (amounts: [String: Int], labels: Set<String>) {
        var amounts: [String: Int] = [:]
        var labels: Set<String> = []
        for t in transactions {
            amounts[Self.duplicateKey(date: t.date, kind: t.kind, amount: t.amount, accountID: t.resolvedAccountID), default: 0] += 1
            if !t.note.isEmpty {
                labels.insert(Self.duplicateLabelKey(date: t.date, label: t.note, accountID: t.resolvedAccountID))
            }
        }
        return (amounts, labels)
    }

    nonisolated static func duplicateKey(date: Date, kind: TransactionKind, amount: Decimal, accountID: String) -> String {
        "\(dayKey(date))|\(kind.rawValue)|\(amount)|\(accountID)"
    }

    nonisolated static func duplicateLabelKey(date: Date, label: String, accountID: String) -> String {
        "\(dayKey(date))|\(StatementParser.normalize(label))|\(accountID)"
    }

    private nonisolated static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}
