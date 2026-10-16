import Foundation

// Virements : deux opérations liées par `transferID` (dépense sur la source, revenu sur la destination).
extension BudgetStore {
    nonisolated static let transferCategoryID = "transfer"
    nonisolated static let defaultTransferNote = "Virement"

    /// Les deux jambes d'un virement (sortante, entrante), nil si incomplet.
    func transferLegs(id: UUID) -> (out: Transaction, in: Transaction)? {
        let legs = transactions.filter { $0.transferID == id }
        guard let out = legs.first(where: { $0.kind == .expense }),
              let incoming = legs.first(where: { $0.kind == .income }) else { return nil }
        return (out, incoming)
    }

    /// Compte situé de l'autre côté du virement.
    func counterpartAccount(of transaction: Transaction) -> Account? {
        guard let id = transaction.transferID, let legs = transferLegs(id: id) else { return nil }
        let other = transaction.kind == .expense ? legs.in : legs.out
        return account(id: other.accountID)
    }

    @discardableResult
    func createTransfer(from: String, to: String, amount: Decimal, date: Date, note: String) -> UUID? {
        guard from != to, amount > 0 else { return nil }
        registerUndo("Créer un virement")
        let id = UUID()
        let cleanNote = Self.cleanTransferNote(note)
        transactions.append(makeLeg(.expense, transferID: id, account: from, amount: amount, date: date, note: cleanNote))
        transactions.append(makeLeg(.income, transferID: id, account: to, amount: amount, date: date, note: cleanNote))
        saveTransactions()
        return id
    }

    func updateTransfer(id: UUID, from: String, to: String, amount: Decimal, date: Date, note: String) {
        guard from != to, amount > 0, transferLegs(id: id) != nil else { return }
        registerUndo("Modifier le virement")
        let cleanNote = Self.cleanTransferNote(note)
        for index in transactions.indices where transactions[index].transferID == id {
            let isOut = transactions[index].kind == .expense
            transactions[index].accountID = Self.storedAccountID(isOut ? from : to)
            transactions[index].amount = amount
            transactions[index].date = date
            transactions[index].note = cleanNote
        }
        saveTransactions()
    }

    func deleteTransfer(id: UUID) {
        registerUndo("Supprimer le virement")
        transactions.removeAll { $0.transferID == id }
        saveTransactions()
    }

    private func makeLeg(_ kind: TransactionKind, transferID: UUID, account: String, amount: Decimal,
                         date: Date, note: String) -> Transaction {
        Transaction(amount: amount, kind: kind, categoryID: Self.transferCategoryID, note: note, date: date,
                    accountID: Self.storedAccountID(account), recurringID: nil, transferID: transferID)
    }

    private nonisolated static func cleanTransferNote(_ note: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTransferNote : trimmed
    }
}
