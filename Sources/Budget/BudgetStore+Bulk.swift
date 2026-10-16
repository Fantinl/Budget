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

    /// Copie les opérations (datées d'aujourd'hui, sans lien récurrent) ; les virements sont ignorés.
    /// Renvoie les copies créées.
    @discardableResult
    func duplicateTransactions(ids: Set<UUID>) -> [Transaction] {
        let copies: [Transaction] = transactions
            .filter { ids.contains($0.id) && !$0.isTransfer }
            .map { source in
                var copy = source
                copy.id = UUID()
                copy.date = .now
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
