import Foundation

// Opérations récurrentes : calcul des échéances et création automatique des opérations.
extension BudgetStore {
    /// Garde-fou : nombre maximal d'opérations créées par récurrente et par appel.
    private static let maxGeneratedPerCall = 500

    /// Crée les opérations des échéances passées non encore générées. Appelée au lancement.
    func generateDueRecurringOperations(now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var created: [Transaction] = []
        var changed = false

        for index in recurringOperations.indices {
            let operation = recurringOperations[index]
            guard operation.isActive else { continue }
            var last = operation.lastGeneratedDate
            var count = 0
            var n = 0
            while count < Self.maxGeneratedPerCall {
                let date = Self.occurrenceDate(of: operation, index: n, calendar: calendar)
                n += 1
                if date > today { break }
                if let end = operation.endDate, date > calendar.startOfDay(for: end) { break }
                if let last, date <= last { continue }
                created.append(Transaction(
                    amount: operation.amount, kind: operation.kind, categoryID: operation.categoryID,
                    note: operation.note.isEmpty ? operation.name : operation.note, date: date,
                    accountID: accountIDForNewTransaction(operation.accountID), recurringID: operation.id))
                last = date
                count += 1
            }
            if last != operation.lastGeneratedDate {
                recurringOperations[index].lastGeneratedDate = last
                changed = true
            }
        }

        if !created.isEmpty {
            transactions.append(contentsOf: created)
            saveTransactions()
        }
        if changed { saveSettings() }
    }

    /// n-ième échéance (0 = première), toujours calculée depuis `startDate`, au début du jour.
    /// Le jour cible est borné au dernier jour du mois s'il n'existe pas (31 → 28/29 février).
    nonisolated static func occurrenceDate(of operation: RecurringOperation, index n: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: operation.startDate)
        let months: Int
        switch operation.frequency {
        case .weekly: return calendar.date(byAdding: .day, value: 7 * n, to: start) ?? start
        case .monthly: months = n
        case .quarterly: months = 3 * n
        case .yearly: months = 12 * n
        }
        let day = calendar.component(.day, from: start)
        guard let firstOfMonth = calendar.dateInterval(of: .month, for: start)?.start,
              let target = calendar.date(byAdding: .month, value: months, to: firstOfMonth),
              let range = calendar.range(of: .day, in: .month, for: target),
              let result = calendar.date(byAdding: .day, value: min(day, range.count) - 1, to: target)
        else { return start }
        return result
    }

    /// Prochaine échéance strictement après `date` (nil si la récurrente est terminée).
    func nextOccurrence(of operation: RecurringOperation, after date: Date = .now) -> Date? {
        let calendar = Calendar.current
        let reference = calendar.startOfDay(for: date)
        let end = operation.endDate.map { calendar.startOfDay(for: $0) }
        for n in 0..<5000 {
            let occurrence = Self.occurrenceDate(of: operation, index: n, calendar: calendar)
            if let end, occurrence > end { return nil }
            if occurrence > reference { return occurrence }
        }
        return nil
    }

    /// Échéances comprises entre `from` et `to` (inclus), au maximum 500.
    func occurrences(of operation: RecurringOperation, from: Date, to: Date) -> [Date] {
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: from)
        let upper = calendar.startOfDay(for: to)
        let end = operation.endDate.map { calendar.startOfDay(for: $0) }
        var result: [Date] = []
        for n in 0..<5000 where result.count < 500 {
            let occurrence = Self.occurrenceDate(of: operation, index: n, calendar: calendar)
            if occurrence > upper || (end.map { occurrence > $0 } ?? false) { break }
            if occurrence >= lower { result.append(occurrence) }
        }
        return result
    }

    func upsertRecurring(_ operation: RecurringOperation) {

        registerUndo("Modifier la récurrente")
        if let index = recurringOperations.firstIndex(where: { $0.id == operation.id }) {
            recurringOperations[index] = operation
        } else {
            recurringOperations.append(operation)
        }
        saveSettings()
        generateDueRecurringOperations()
    }

    /// Supprime la récurrente ; les opérations déjà créées sont conservées.
    func deleteRecurring(_ operation: RecurringOperation) {
        registerUndo("Supprimer la récurrente")
        recurringOperations.removeAll { $0.id == operation.id }
        saveSettings()
    }
}
