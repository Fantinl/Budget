import Foundation

/// Fusion pure de deux instantanés (aucune E/S), indépendante du transport.
///
/// Règles :
/// - union par identifiant ; pour un même id, la version modifiée le plus récemment gagne ;
/// - une suppression gagne si elle est strictement plus récente que la dernière modification ;
/// - l'ordre d'une liste suit la version dont l'horodatage d'ordre est le plus récent, puis les éléments
///   qu'elle ne connaît pas sont ajoutés à la fin (dans l'ordre de l'autre) ;
/// - un réglage simple (compte par défaut) : horodatage le plus récent ;
/// - égalité parfaite : l'appareil au plus grand identifiant l'emporte (même résultat dans les deux sens) ;
/// - les tombes de plus de 90 jours sont purgées.
enum SyncMerge {
    static let tombstoneLifetime: TimeInterval = 90 * 24 * 3600

    static func merge(local: SyncSnapshot, remote: SyncSnapshot, now: Date = .now) -> SyncSnapshot {
        var ctx = Context(local: local, remote: remote)
        var out = SyncSnapshot(deviceID: max(local.deviceID, remote.deviceID), date: max(local.date, remote.date))

        let tx = ctx.records(SyncKey.transaction, local.transactions, remote.transactions) { $0.id.uuidString }
        out.transactions = tx.values.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
        let cats = ctx.records(SyncKey.category, local.categories, remote.categories) { $0.id }
        out.categories = ctx.ordered(SyncKey.orderCategories, cats, local.categories.map(\.id), remote.categories.map(\.id))
        let accs = ctx.records(SyncKey.account, local.accounts, remote.accounts) { $0.id }
        out.accounts = ctx.ordered(SyncKey.orderAccounts, accs, local.accounts.map(\.id), remote.accounts.map(\.id))
        let quick = ctx.records(SyncKey.quick, local.quickExpenses, remote.quickExpenses) { $0.id.uuidString }
        out.quickExpenses = ctx.ordered(SyncKey.orderQuick, quick, local.quickExpenses.map { $0.id.uuidString },
                                        remote.quickExpenses.map { $0.id.uuidString })
        let recs = ctx.records(SyncKey.recurring, local.recurringOperations, remote.recurringOperations) { $0.id.uuidString }
        out.recurringOperations = ctx.ordered(SyncKey.orderRecurring, recs, local.recurringOperations.map { $0.id.uuidString },
                                              remote.recurringOperations.map { $0.id.uuidString })
        let tags = ctx.records(SyncKey.tag, local.tags, remote.tags) { $0.id }
        out.tags = ctx.ordered(SyncKey.orderTags, tags, local.tags.map(\.id), remote.tags.map(\.id))

        let (account, accountStamp) = ctx.scalar(SyncKey.defaultAccount, local.defaultAccountID, remote.defaultAccountID)
        out.defaultAccountID = account
        ctx.settingsAt[SyncKey.defaultAccount] = accountStamp
        let (plan, planStamp) = ctx.scalar(SyncKey.budgetPlan, local.budgetPlan, remote.budgetPlan)
        out.budgetPlan = plan
        ctx.settingsAt[SyncKey.budgetPlan] = planStamp

        out.modifiedAt = ctx.modifiedAt
        out.settingsAt = ctx.settingsAt.filter { $0.value > .distantPast }
        out.deletedAt = ctx.tombstones(now: now)
        return out
    }

    /// Données de travail d'une fusion.
    private struct Context {
        let local: SyncSnapshot
        let remote: SyncSnapshot
        let preferLocal: Bool
        var survivors: Set<String> = []
        var modifiedAt: [String: Date] = [:]
        var settingsAt: [String: Date] = [:]

        init(local: SyncSnapshot, remote: SyncSnapshot) {
            self.local = local
            self.remote = remote
            preferLocal = local.deviceID >= remote.deviceID
        }

        /// Fusionne une collection : renvoie les enregistrements survivants par identifiant.
        mutating func records<T>(_ prefix: String, _ l: [T], _ r: [T], id: (T) -> String) -> [String: T] {
            let lMap = Dictionary(l.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
            let rMap = Dictionary(r.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
            var result: [String: T] = [:]
            for key in Set(lMap.keys).union(rMap.keys) {
                let k = prefix + key
                let lStamp = local.modifiedAt[k] ?? .distantPast
                let rStamp = remote.modifiedAt[k] ?? .distantPast
                let item: T, stamp: Date
                if let li = lMap[key], let ri = rMap[key] {
                    let useLocal = lStamp != rStamp ? lStamp > rStamp : preferLocal
                    (item, stamp) = useLocal ? (li, lStamp) : (ri, rStamp)
                } else if let li = lMap[key] {
                    (item, stamp) = (li, lStamp)
                } else {
                    (item, stamp) = (rMap[key]!, rStamp)
                }
                let deleted = max(local.deletedAt[k] ?? .distantPast, remote.deletedAt[k] ?? .distantPast)
                if deleted > stamp { continue }
                result[key] = item
                survivors.insert(k)
                if stamp > .distantPast { modifiedAt[k] = stamp }
            }
            return result
        }

        /// Ordre d'une liste : celui de la version la plus récente, puis les inconnus de l'autre.
        mutating func ordered<T>(_ key: String, _ items: [String: T], _ l: [String], _ r: [String]) -> [T] {
            let lStamp = local.settingsAt[key] ?? .distantPast
            let rStamp = remote.settingsAt[key] ?? .distantPast
            let useLocal = lStamp != rStamp ? lStamp > rStamp : preferLocal
            settingsAt[key] = max(lStamp, rStamp)
            var seen = Set<String>()
            var out: [T] = []
            for id in (useLocal ? l + r : r + l) where seen.insert(id).inserted {
                if let item = items[id] { out.append(item) }
            }
            return out
        }

        /// Réglage simple : la valeur la plus récemment modifiée.
        func scalar<V>(_ key: String, _ l: V, _ r: V) -> (V, Date) {
            let lStamp = local.settingsAt[key] ?? .distantPast
            let rStamp = remote.settingsAt[key] ?? .distantPast
            let useLocal = lStamp != rStamp ? lStamp > rStamp : preferLocal
            return (useLocal ? l : r, max(lStamp, rStamp))
        }

        /// Tombes conservées : celles des enregistrements non survivants, de moins de 90 jours.
        func tombstones(now: Date) -> [String: Date] {
            var out: [String: Date] = [:]
            let cutoff = now.addingTimeInterval(-SyncMerge.tombstoneLifetime)
            for (k, d) in local.deletedAt.merging(remote.deletedAt, uniquingKeysWith: max)
            where !survivors.contains(k) && d >= cutoff {
                out[k] = d
            }
            return out
        }
    }
}
