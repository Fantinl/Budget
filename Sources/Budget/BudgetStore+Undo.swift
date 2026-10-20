import Foundation

// Annuler / Rétablir (⌘Z / ⇧⌘Z) : avant chaque modification, on enregistre une photo des données.
// Annuler restaure la photo (et enregistre l'état courant pour pouvoir rétablir).
extension BudgetStore {
    struct UndoSnapshot {
        var transactions: [Transaction]
        var categories: [Category]
        var quickExpenses: [QuickExpense]
        var accounts: [Account]
        var recurringOperations: [RecurringOperation]
        var defaultAccountID: String
        var tags: [Tag]
    }

    private var snapshot: UndoSnapshot {
        UndoSnapshot(transactions: transactions, categories: categories, quickExpenses: quickExpenses,
                     accounts: accounts, recurringOperations: recurringOperations, defaultAccountID: defaultAccountID, tags: tags)
    }

    /// À appeler au début de toute modification faite par l'utilisateur.
    /// Plusieurs appels dans une même action sont regroupés en une seule étape d'annulation.
    func registerUndo(_ actionName: String) {
        guard let undoManager else { return }
        let before = snapshot
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(before, actionName: actionName) }
        }
        undoManager.setActionName(actionName)
    }

    private func restore(_ state: UndoSnapshot, actionName: String) {
        registerUndo(actionName) // permet de rétablir
        transactions = state.transactions
        categories = state.categories
        quickExpenses = state.quickExpenses
        accounts = state.accounts
        recurringOperations = state.recurringOperations
        defaultAccountID = state.defaultAccountID
        tags = state.tags
        saveTransactions()
        saveSettings()
    }
}
