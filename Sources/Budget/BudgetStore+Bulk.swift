import Foundation

// Actions groupées sur plusieurs opérations : une seule étape d'annulation et une seule sauvegarde.
extension BudgetStore {
    /// Applique une modification aux opérations données (les virements sont ignorés).
    /// Renvoie le nombre d'opérations modifiées.
    @discardableResult
    func updateTransactions(ids: Set<UUID>, _ change: (inout Transaction) -> Void) -> Int {
        guard transactions.contains(where: { ids.contains($0.id) && !$0.isTransfer }) else { return 0 }
        registerUndo("Modifier les opérations")
        var count = 0
        for index in transactions.indices where ids.contains(transactions[index].id) && !transactions[index].isTransfer {
            change(&transactions[index])
            count += 1
        }
        saveTransactions()
        return count
    }

    /// Supprime les opérations données, avec la jambe jumelle des virements (même `transferID`).
    /// Renvoie le nombre d'opérations supprimées.
    @discardableResult
    func deleteTransactions(ids: Set<UUID>) -> Int {
        let transferIDs = Set(transactions.filter { ids.contains($0.id) }.compactMap(\.transferID))
        let doomed = { (t: Transaction) in
            ids.contains(t.id) || (t.transferID.map(transferIDs.contains) ?? false)
        }
        let count = transactions.filter(doomed).count
        guard count > 0 else { return 0 }
        registerUndo(count > 1 ? "Supprimer les opérations" : "Supprimer l’opération")
        transactions.removeAll(where: doomed)
        saveTransactions()
        return count
    }

    /// Copie les opérations (même date que l'original, sans lien récurrent) ; les virements sont ignorés.
    /// Renvoie les copies créées.
    @discardableResult
    func duplicateTransactions(ids: Set<UUID>) -> [Transaction] {
        let copies: [Transaction] = transactions
            .filter { ids.contains($0.id) && !$0.isTransfer }
            .map { source in
                var copy = source
                copy.id = UUID() // même date que l'original
                copy.recurringID = nil
                return copy
            }
        guard !copies.isEmpty else { return [] }
        registerUndo("Dupliquer les opérations")
        transactions.append(contentsOf: copies)
        saveTransactions()
        return copies
    }
}

// MARK: - Tags en lot

/// État d'un tag dans une sélection.
enum BulkTagState: Equatable {
    case all, some, none
}

extension BudgetStore {
    /// Identifiants donnés + jambe jumelle des virements (les tags valent pour les deux jambes).
    private func idsWithTransferTwins(_ ids: Set<UUID>) -> Set<UUID> {
        let transferIDs = Set(transactions.filter { ids.contains($0.id) }.compactMap(\.transferID))
        guard !transferIDs.isEmpty else { return ids }
        return ids.union(transactions.filter { $0.transferID.map(transferIDs.contains) ?? false }.map(\.id))
    }

    /// Le tag est-il porté par toutes, certaines ou aucune des opérations ?
    func tagState(_ tag: Tag, in ids: Set<UUID>) -> BulkTagState {
        let targets = transactions.filter { idsWithTransferTwins(ids).contains($0.id) }
        let count = targets.filter { ($0.tagIDs ?? []).contains(tag.id) }.count
        if count == 0 { return .none }
        return count == targets.count ? .all : .some
    }

    /// Ajoute le tag à toutes les opérations (virements compris, deux jambes).
    func addTag(_ tag: Tag, to ids: Set<UUID>) {
        changeTags(ids, "Ajouter le tag") { tagIDs in
            if !tagIDs.contains(tag.id) { tagIDs.append(tag.id) }
        }
    }

    /// Retire le tag de toutes les opérations (virements compris, deux jambes).
    func removeTag(_ tag: Tag, from ids: Set<UUID>) {
        changeTags(ids, "Retirer le tag") { $0.removeAll { $0 == tag.id } }
    }

    /// Retire tous les tags des opérations.
    func removeAllTags(from ids: Set<UUID>) {
        changeTags(ids, "Retirer les tags") { $0.removeAll() }
    }

    private func changeTags(_ ids: Set<UUID>, _ name: String, _ change: (inout [String]) -> Void) {
        let all = idsWithTransferTwins(ids)
        guard transactions.contains(where: { all.contains($0.id) }) else { return }
        registerUndo(name)
        for index in transactions.indices where all.contains(transactions[index].id) {
            var tagIDs = transactions[index].tagIDs ?? []
            change(&tagIDs)
            transactions[index].tagIDs = tagIDs.isEmpty ? nil : tagIDs
        }
        saveTransactions()
    }
}

// MARK: - Modification groupée

/// Changements à appliquer ; un champ à nil n'est pas touché.
struct BulkEdit: Equatable {
    var amount: Decimal?
    var kind: TransactionKind?
    var categoryID: String?
    /// Identifiant de compte (principal inclus).
    var accountID: String?
    var note: String?
    var addTagIDs: [String] = []
    var removeTagIDs: [String] = []

    var isEmpty: Bool {
        amount == nil && kind == nil && categoryID == nil && accountID == nil && note == nil
            && addTagIDs.isEmpty && removeTagIDs.isEmpty
    }
}

/// Valeurs communes à une sélection : nil quand les opérations diffèrent.
struct BulkSummary {
    let count: Int
    let amount: Decimal?
    let kind: TransactionKind?
    let categoryID: String?
    let accountID: String?
    let note: String?
    let tagIDs: [String]?
    let firstDate: Date?
    let lastDate: Date?

    init(_ items: [Transaction]) {
        count = items.count
        func common<V: Equatable>(_ key: (Transaction) -> V) -> V? {
            guard let first = items.first.map(key), items.allSatisfy({ key($0) == first }) else { return nil }
            return first
        }
        amount = common(\.amount)
        kind = common(\.kind)
        categoryID = common(\.categoryID)
        accountID = common(\.resolvedAccountID)
        note = common(\.note)
        tagIDs = common { Set($0.tagIDs ?? []).sorted() }
        firstDate = items.map(\.date).min()
        lastDate = items.map(\.date).max()
    }

    /// Toutes les opérations ont les mêmes valeurs.
    var isUniform: Bool {
        count > 0 && amount != nil && kind != nil && categoryID != nil && accountID != nil && note != nil && tagIDs != nil
    }
}

extension BudgetStore {
    /// Applique une modification groupée (virements ignorés, dates conservées) :
    /// une seule annulation, une seule sauvegarde. Renvoie le nombre d'opérations modifiées.
    @discardableResult
    func applyBulkEdit(ids: Set<UUID>, _ edit: BulkEdit) -> Int {
        let count = transactions.filter { ids.contains($0.id) && !$0.isTransfer }.count
        guard count > 0, !edit.isEmpty else { return 0 }
        registerUndo(count > 1 ? "Modifier \(count) opérations" : "Modifier l’opération")
        let stored = edit.accountID.map(Self.storedAccountID)
        for index in transactions.indices where ids.contains(transactions[index].id) && !transactions[index].isTransfer {
            var t = transactions[index]
            if let amount = edit.amount { t.amount = amount }
            if let kind = edit.kind { t.kind = kind }
            if let stored { t.accountID = stored }
            if let note = edit.note { t.note = note }
            applyCategory(edit, to: &t)
            applyTags(edit, to: &t)
            transactions[index] = t
        }
        saveTransactions()
        return count
    }

    /// Catégorie demandée si elle correspond au type final ; sinon, au changement de type, la première du type.
    private func applyCategory(_ edit: BulkEdit, to t: inout Transaction) {
        if let id = edit.categoryID, category(id: id).kind == t.kind {
            t.categoryID = id
        } else if edit.kind != nil, category(id: t.categoryID).kind != t.kind {
            t.categoryID = categories(for: t.kind).first?.id ?? t.categoryID
        }
    }

    private func applyTags(_ edit: BulkEdit, to t: inout Transaction) {
        guard !edit.addTagIDs.isEmpty || !edit.removeTagIDs.isEmpty else { return }
        var ids = t.tagIDs ?? []
        ids.removeAll { edit.removeTagIDs.contains($0) }
        for id in edit.addTagIDs where !ids.contains(id) { ids.append(id) }
        t.tagIDs = ids.isEmpty ? nil : ids
    }
}
