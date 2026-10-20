import Foundation

// Pont entre le magasin et la synchronisation : instantané local, application d'un résultat de fusion.
extension BudgetStore {
    var syncMetaURL: URL { directory.appending(path: "sync-meta.json") }

    /// Appareil neuf : aucune donnée suivie (le premier échange adopte alors simplement le distant).
    var isSyncPristine: Bool { sync.meta.isEmpty }

    func makeSyncSnapshot() -> SyncSnapshot {
        SyncSnapshot(deviceID: sync.meta.deviceID, date: sync.clock(),
                     transactions: transactions, categories: categories, quickExpenses: quickExpenses,
                     accounts: accounts, recurringOperations: recurringOperations, tags: tags,
                     defaultAccountID: defaultAccountID, modifiedAt: sync.meta.modifiedAt,
                     deletedAt: sync.meta.deletedAt, settingsAt: sync.meta.settingsAt)
    }

    /// Remplace les données par le résultat d'une fusion, sans créer de « modifications » artificielles.
    /// Renvoie vrai si quelque chose a changé. L'historique d'annulation est alors vidé :
    /// un ⌘Z restaurerait tout l'ancien état et effacerait ce qui vient de l'autre appareil.
    @discardableResult
    func applySyncSnapshot(_ s: SyncSnapshot) -> Bool {
        sync.isSuspended = true
        defer { sync.isSuspended = false }
        let txChanged = transactions != s.transactions
        let settingsChanged = categories != s.categories || quickExpenses != s.quickExpenses
            || accounts != s.accounts || recurringOperations != s.recurringOperations
            || tags != s.tags || defaultAccountID != s.defaultAccountID
        if txChanged { transactions = s.transactions }
        if settingsChanged {
            categories = s.categories
            quickExpenses = s.quickExpenses
            accounts = s.accounts
            recurringOperations = s.recurringOperations
            tags = s.tags
            defaultAccountID = s.defaultAccountID
            ensureRequiredRecords()
        }
        if txChanged { saveTransactions() }
        if settingsChanged { saveSettings() }
        sync.meta.modifiedAt = s.modifiedAt
        sync.meta.deletedAt = s.deletedAt
        sync.meta.settingsAt = s.settingsAt
        sync.baseline = SyncTracker.makeBaseline(self)
        sync.persist(to: syncMetaURL)
        if txChanged || settingsChanged { undoManager?.removeAllActions() }
        return txChanged || settingsChanged
    }
}
