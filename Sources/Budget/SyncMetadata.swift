import Foundation

// Suivi des modifications pour la synchronisation entre appareils.
// Les métadonnées vivent dans `sync-meta.json` : transactions.json et settings.json ne changent pas.

/// Clés des enregistrements : « type:identifiant », pour éviter les collisions entre types.
enum SyncKey {
    static let transaction = "tx:"
    static let category = "cat:"
    static let account = "acc:"
    static let quick = "quick:"
    static let recurring = "rec:"
    static let tag = "tag:"

    /// Réglages simples (horodatage unique) : compte par défaut et ordre de chaque liste.
    static let defaultAccount = "defaultAccount"
    static let orderCategories = "order.categories"
    static let orderAccounts = "order.accounts"
    static let orderQuick = "order.quickExpenses"
    static let orderTags = "order.tags"
    static let orderRecurring = "order.recurring"
}

/// Dates de modification / suppression de chaque enregistrement de cet appareil.
struct SyncMetadata: Codable, Equatable, Sendable {
    var deviceID = UUID().uuidString
    var modifiedAt: [String: Date] = [:]
    var deletedAt: [String: Date] = [:]
    var settingsAt: [String: Date] = [:]

    /// Rien n'a jamais été modifié ni supprimé : appareil tout neuf.
    var isEmpty: Bool { modifiedAt.isEmpty && deletedAt.isEmpty && settingsAt.isEmpty }
}

/// Tout l'état échangé entre appareils (format versionné).
struct SyncSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version = SyncSnapshot.currentVersion
    var deviceID: String
    var date: Date
    var transactions: [Transaction] = []
    var categories: [Category] = []
    var quickExpenses: [QuickExpense] = []
    var accounts: [Account] = []
    var recurringOperations: [RecurringOperation] = []
    var tags: [Tag] = []
    var defaultAccountID = Account.mainID
    var modifiedAt: [String: Date] = [:]
    var deletedAt: [String: Date] = [:]
    var settingsAt: [String: Date] = [:]

    /// Instantané vide (distant inexistant).
    static var empty: SyncSnapshot { SyncSnapshot(deviceID: "", date: .distantPast) }

    /// Même contenu, sans tenir compte de l'appareil ni de la date d'écriture.
    func sameContent(as other: SyncSnapshot) -> Bool {
        var a = self, b = other
        a.deviceID = ""; b.deviceID = ""
        a.date = .distantPast; b.date = .distantPast
        return a == b
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder   // dates en secondes : aucune perte de précision pour comparer les horodatages
    }()
    static let decoder = JSONDecoder()
}

/// État de référence : ce qui a été enregistré la dernière fois, pour détecter les différences.
struct SyncBaseline {
    var transactions: [String: Transaction] = [:]
    var categories: [String: Category] = [:]
    var quickExpenses: [String: QuickExpense] = [:]
    var accounts: [String: Account] = [:]
    var recurring: [String: RecurringOperation] = [:]
    var tags: [String: Tag] = [:]
    var orders: [String: [String]] = [:]
    var defaultAccountID = Account.mainID
}

/// Compare l'état courant au dernier état enregistré et tient les horodatages à jour.
/// Appelé depuis `saveTransactions()` / `saveSettings()` : aucune fonction de mutation n'a à s'en soucier.
@MainActor
final class SyncTracker {
    var meta = SyncMetadata()
    var baseline: SyncBaseline?
    /// Vrai pendant l'application d'une synchronisation : pas de « modifications » artificielles.
    var isSuspended = false
    /// Horloge injectable (tests).
    var clock: () -> Date = { .now }
    /// Appelé après une modification locale (le coordinateur y accroche son anti-rebond).
    var onLocalChange: (@MainActor () -> Void)?

    /// Appelé à la fin de `reloadFromDisk()`.
    /// 1er chargement : lit les métadonnées, ou date tout par le fichier existant.
    /// Rechargements (restauration, import) : les différences comptent comme des modifications.
    func didReload(_ store: BudgetStore) {
        guard baseline != nil else {
            if let loaded = Self.loadMeta(store.syncMetaURL) {
                meta = loaded
            } else {
                meta = SyncMetadata()
                stampExisting(store)
            }
            baseline = Self.makeBaseline(store)
            return
        }
        trackTransactions(store)
        trackSettings(store)
    }

    private func stampExisting(_ store: BudgetStore) {
        func modDate(_ url: URL) -> Date? {
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        if let date = modDate(store.transactionsURL) {
            for t in store.transactions { meta.modifiedAt[SyncKey.transaction + t.id.uuidString] = date }
        }
        guard let date = modDate(store.settingsURL) else { return }
        for c in store.categories { meta.modifiedAt[SyncKey.category + c.id] = date }
        for a in store.accounts { meta.modifiedAt[SyncKey.account + a.id] = date }
        for q in store.quickExpenses { meta.modifiedAt[SyncKey.quick + q.id.uuidString] = date }
        for r in store.recurringOperations { meta.modifiedAt[SyncKey.recurring + r.id.uuidString] = date }
        for t in store.tags { meta.modifiedAt[SyncKey.tag + t.id] = date }
        for key in [SyncKey.defaultAccount, SyncKey.orderCategories, SyncKey.orderAccounts,
                    SyncKey.orderQuick, SyncKey.orderTags, SyncKey.orderRecurring] {
            meta.settingsAt[key] = date
        }
    }

    static func makeBaseline(_ store: BudgetStore) -> SyncBaseline {
        var b = SyncBaseline()
        b.transactions = index(store.transactions) { $0.id.uuidString }
        b.categories = index(store.categories) { $0.id }
        b.quickExpenses = index(store.quickExpenses) { $0.id.uuidString }
        b.accounts = index(store.accounts) { $0.id }
        b.recurring = index(store.recurringOperations) { $0.id.uuidString }
        b.tags = index(store.tags) { $0.id }
        b.orders = orders(of: store)
        b.defaultAccountID = store.defaultAccountID
        return b
    }

    private static func index<T>(_ items: [T], key: (T) -> String) -> [String: T] {
        Dictionary(items.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func orders(of store: BudgetStore) -> [String: [String]] {
        [SyncKey.orderCategories: store.categories.map(\.id),
         SyncKey.orderAccounts: store.accounts.map(\.id),
         SyncKey.orderQuick: store.quickExpenses.map { $0.id.uuidString },
         SyncKey.orderTags: store.tags.map(\.id),
         SyncKey.orderRecurring: store.recurringOperations.map { $0.id.uuidString }]
    }

    // MARK: - Détection

    func trackTransactions(_ store: BudgetStore) {
        guard !isSuspended, var base = baseline else { return }
        let changed = track(store.transactions, prefix: SyncKey.transaction, old: &base.transactions) { $0.id.uuidString }
        baseline = base
        finish(changed, store)
    }

    func trackSettings(_ store: BudgetStore) {
        guard !isSuspended, var base = baseline else { return }
        var changed = track(store.categories, prefix: SyncKey.category, old: &base.categories) { $0.id }
        changed = track(store.accounts, prefix: SyncKey.account, old: &base.accounts) { $0.id } || changed
        changed = track(store.quickExpenses, prefix: SyncKey.quick, old: &base.quickExpenses) { $0.id.uuidString } || changed
        changed = track(store.recurringOperations, prefix: SyncKey.recurring, old: &base.recurring) { $0.id.uuidString } || changed
        changed = track(store.tags, prefix: SyncKey.tag, old: &base.tags) { $0.id } || changed
        changed = trackSimpleSettings(store, base: &base) || changed
        baseline = base
        finish(changed, store)
    }

    private func trackSimpleSettings(_ store: BudgetStore, base: inout SyncBaseline) -> Bool {
        let now = clock()
        var changed = false
        if base.defaultAccountID != store.defaultAccountID {
            meta.settingsAt[SyncKey.defaultAccount] = now
            base.defaultAccountID = store.defaultAccountID
            changed = true
        }
        for (key, ids) in Self.orders(of: store) {
            let old = base.orders[key] ?? []
            if Self.relativeOrderChanged(old: old, new: ids) { meta.settingsAt[key] = now; changed = true }
            base.orders[key] = ids
        }
        return changed
    }

    /// L'ordre a changé pour les éléments présents avant et après (ajouts et suppressions ne comptent pas).
    static func relativeOrderChanged(old: [String], new: [String]) -> Bool {
        let oldSet = Set(old), newSet = Set(new)
        return old.filter { newSet.contains($0) } != new.filter { oldSet.contains($0) }
    }

    private func track<T: Equatable>(_ items: [T], prefix: String, old: inout [String: T],
                                     key: (T) -> String) -> Bool {
        let now = clock()
        var current: [String: T] = [:]
        current.reserveCapacity(items.count)
        var changed = false
        for item in items {
            let id = key(item)
            current[id] = item
            if old[id] != item {
                meta.modifiedAt[prefix + id] = now
                meta.deletedAt[prefix + id] = nil
                changed = true
            }
        }
        for id in old.keys where current[id] == nil {
            meta.deletedAt[prefix + id] = now
            meta.modifiedAt[prefix + id] = nil
            changed = true
        }
        old = current
        return changed
    }

    private func finish(_ changed: Bool, _ store: BudgetStore) {
        guard changed else { return }
        persist(to: store.syncMetaURL)
        onLocalChange?()
    }

    // MARK: - Disque

    func persist(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? SyncSnapshot.encoder.encode(meta) { try? data.write(to: url, options: .atomic) }
    }

    static func loadMeta(_ url: URL) -> SyncMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SyncSnapshot.decoder.decode(SyncMetadata.self, from: data)
    }
}
