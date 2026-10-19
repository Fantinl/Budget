import Foundation

extension BudgetStore {
    /// Ajoute les opérations importées en une seule fois (une seule sauvegarde).
    func addImported(_ imported: [Transaction]) {
        addImported(imported, recharges: [], from: Account.mainID)
    }

    /// Variante avec recharges Izly : chacune devient un virement `account` -> compte Izly,
    /// le tout dans la même opération annulable et la même sauvegarde.
    func addImported(_ imported: [Transaction], recharges: [ImportRecharge], from account: String) {
        registerUndo("Importer le relevé")
        guard !imported.isEmpty || !recharges.isEmpty else { return }
        transactions.append(contentsOf: imported)
        for recharge in recharges where recharge.izlyAccountID != account && recharge.amount > 0 {
            let id = UUID()
            let note = recharge.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = note.isEmpty ? Self.defaultTransferNote : note
            transactions.append(Transaction(amount: recharge.amount, kind: .expense, categoryID: Self.transferCategoryID,
                                            note: text, date: recharge.date, accountID: Self.storedAccountID(account),
                                            recurringID: nil, transferID: id))
            transactions.append(Transaction(amount: recharge.amount, kind: .income, categoryID: Self.transferCategoryID,
                                            note: text, date: recharge.date, accountID: Self.storedAccountID(recharge.izlyAccountID),
                                            recurringID: nil, transferID: id))
        }
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
