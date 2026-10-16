import Foundation

// Comptes : liste, soldes et opérations par compte.
// À faire : virements entre comptes (deux opérations liées, hors revenus/dépenses du mois).
extension BudgetStore {
    func account(id: String?) -> Account {
        accounts.first { $0.id == (id ?? Account.mainID) } ?? .main
    }

    // MARK: Compte par défaut
    //
    // Dans une `Transaction`, accountID nil = compte principal (données historiques).
    // Dans une dépense rapide ou une récurrente, accountID nil = compte par défaut du moment.

    /// Compte par défaut ; retombe sur le compte principal s'il a été archivé ou supprimé.
    var defaultAccount: Account {
        activeAccounts.first { $0.id == defaultAccountID } ?? account(id: Account.mainID)
    }

    func setDefaultAccount(_ account: Account) {

        registerUndo("Changer le compte par défaut")
        defaultAccountID = account.id
        saveSettings()
    }

    /// Valeur à enregistrer dans `Transaction.accountID` (nil pour le compte principal).
    nonisolated static func storedAccountID(_ id: String) -> String? {
        id == Account.mainID ? nil : id
    }

    /// Compte d'une nouvelle opération : celui demandé, sinon le compte par défaut.
    func accountIDForNewTransaction(_ requested: String? = nil) -> String? {
        Self.storedAccountID(requested ?? defaultAccount.id)
    }

    /// Opération issue d'une dépense rapide (sans compte précis → compte par défaut).
    func makeTransaction(from quick: QuickExpense, date: Date = .now) -> Transaction {
        var transaction = quick.makeTransaction(date: date)
        transaction.accountID = accountIDForNewTransaction(quick.accountID)
        return transaction
    }

    /// Comptes non archivés, dans l'ordre choisi.
    var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    func upsertAccount(_ account: Account) {

        registerUndo("Modifier le compte")
        var account = account
        // Le compte principal ne peut pas être archivé.
        if account.id == Account.mainID { account.isArchived = false }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        saveSettings()
    }

    func archiveAccount(_ account: Account) {

        registerUndo("Archiver le compte")
        setArchived(account, true)
    }

    func unarchiveAccount(_ account: Account) {

        registerUndo("Désarchiver le compte")
        setArchived(account, false)
    }

    private func setArchived(_ account: Account, _ archived: Bool) {
        guard account.id != Account.mainID,
              let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].isArchived = archived
        saveSettings()
    }

    /// Supprime un compte sans opération (ni le compte principal). Renvoie false si refusé.
    @discardableResult
    func deleteAccount(_ account: Account) -> Bool {
        registerUndo("Supprimer le compte")
        guard account.id != Account.mainID, usageCount(of: account) == 0 else { return false }
        accounts.removeAll { $0.id == account.id }
        saveSettings()
        return true
    }

    func moveAccounts(from source: IndexSet, to destination: Int) {

        registerUndo("Réordonner les comptes")
        accounts.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }

    /// Opérations d'un compte (toutes dates), de la plus récente à la plus ancienne.
    func transactions(of account: Account) -> [Transaction] {
        transactions
            .filter { $0.resolvedAccountID == account.id }
            .sorted { $0.date > $1.date }
    }

    /// Nombre d'opérations rattachées au compte.
    func usageCount(of account: Account) -> Int {
        transactions.reduce(0) { $0 + ($1.resolvedAccountID == account.id ? 1 : 0) }
    }

    /// Solde initial + revenus − dépenses du compte, jusqu'à la date (incluse).
    func balance(of account: Account, asOf date: Date = .now) -> Decimal {
        transactions.reduce(account.initialBalance) { total, t in
            t.resolvedAccountID == account.id && t.date <= date ? total + t.signedAmount : total
        }
    }

    /// Valeur du compte : valorisation saisie pour un placement, sinon le solde.
    func value(of account: Account) -> Decimal {
        account.kind.hasMarketValue ? (account.marketValue ?? balance(of: account)) : balance(of: account)
    }

    /// Plus ou moins-value d'un placement (valorisation − versements), nil sans valorisation.
    func gain(of account: Account) -> Decimal? {
        guard account.kind.hasMarketValue, let marketValue = account.marketValue else { return nil }
        return marketValue - balance(of: account)
    }

    /// Somme des valeurs des comptes non archivés (patrimoine).
    func totalBalance(asOf date: Date = .now) -> Decimal {
        activeAccounts.reduce(0) { $0 + (Calendar.current.isDateInToday(date) ? value(of: $1) : balance(of: $1, asOf: date)) }
    }

    /// Banques déjà saisies (pour les suggestions et le regroupement), triées.
    var banks: [String] {
        Array(Set(accounts.compactMap { $0.bank?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
