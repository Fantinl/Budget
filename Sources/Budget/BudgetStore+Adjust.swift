import Foundation

// Ajustement de solde : on recopie le solde réel, Budget enregistre la différence.
extension BudgetStore {
    /// Écart entre le solde réel et celui de Budget (négatif = dépenses non notées).
    func balanceGap(of account: Account, to realBalance: Decimal, asOf date: Date = .now) -> Decimal {
        realBalance - balance(of: account, asOf: date)
    }

    /// Crée la dépense (écart négatif) ou le revenu (écart positif) qui ramène le solde à `realBalance`.
    /// Rien si l'écart est nul. `categoryID` sert pour une dépense ; un revenu va en « Autre revenu ».
    @discardableResult
    func adjustBalance(of account: Account, to realBalance: Decimal, date: Date = .now,
                       categoryID: String, note: String) -> Transaction? {
        let gap = balanceGap(of: account, to: realBalance, asOf: date)
        guard gap != 0 else { return nil }
        registerUndo("Ajuster le solde")
        let transaction = Transaction(
            amount: abs(gap),
            kind: gap < 0 ? .expense : .income,
            categoryID: gap < 0 ? categoryID : "otherIncome",
            note: note,
            date: date,
            accountID: Self.storedAccountID(account.id))
        transactions.append(transaction)
        saveTransactions()
        return transaction
    }
}
