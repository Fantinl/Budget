import Foundation

/// Une récurrente à venir d'ici la fin du mois.
struct UpcomingRecurring: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    /// Montant signé (négatif pour une dépense).
    let amount: Decimal
}

/// Prévision du solde du mois en fin de mois.
struct MonthForecast {
    /// Revenus − dépenses du mois à ce jour (hors virements).
    let current: Decimal
    /// Récurrentes actives à venir (de demain à la fin du mois), triées par date.
    let upcoming: [UpcomingRecurring]
    /// Dépenses courantes restantes estimées (positif), nil si historique insuffisant.
    let estimatedSpending: Decimal?
    /// Moyenne journalière utilisée pour l'estimation.
    let dailyAverage: Decimal?

    var upcomingTotal: Decimal { upcoming.reduce(0) { $0 + $1.amount } }
    var projected: Decimal { current + upcomingTotal - (estimatedSpending ?? 0) }
}

extension BudgetStore {
    /// Récurrentes actives à venir (demain → fin du mois), éventuellement pour un seul compte.
    func upcomingRecurring(now: Date = .now, accountID: String? = nil) -> [UpcomingRecurring] {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
              let monthEnd = cal.dateInterval(of: .month, for: now)?.end,
              let lastDay = cal.date(byAdding: .day, value: -1, to: monthEnd), tomorrow <= lastDay
        else { return [] }
        var result: [UpcomingRecurring] = []
        for operation in recurringOperations where operation.isActive {
            let resolved = operation.accountID ?? defaultAccount.id
            if let accountID, resolved != accountID { continue }
            let signed = operation.kind == .expense ? -operation.amount : operation.amount
            for date in occurrences(of: operation, from: tomorrow, to: lastDay) {
                result.append(UpcomingRecurring(name: operation.name, date: date, amount: signed))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Prévision de fin de mois pour le mois en cours (tous comptes).
    func monthForecast(now: Date = .now) -> MonthForecast {
        let cal = Calendar.current
        let monthTransactions = transactions(inMonthOf: now)
        let current = monthTransactions.reduce(Decimal(0)) { total, t in
            t.isSpending ? total - t.amount : (t.isEarning ? total + t.amount : total)
        }

        // Moyenne journalière des dépenses non récurrentes des 3 mois précédents.
        // Il faut au moins 2 de ces mois avec des dépenses, sinon pas d'estimation.
        let monthStart = now.startOfMonth
        var days = 0
        var total: Decimal = 0
        var monthsWithSpending = 0
        for back in 1...3 {
            let month = monthStart.addingMonths(-back)
            let spending = transactions(inMonthOf: month).filter { $0.isSpending && $0.recurringID == nil }
            guard !spending.isEmpty else { continue }
            monthsWithSpending += 1
            total += spending.reduce(0) { $0 + $1.amount }
            days += cal.range(of: .day, in: .month, for: month)?.count ?? 30
        }
        var estimate: Decimal?
        var average: Decimal?
        if monthsWithSpending >= 2, days > 0 {
            let daily = total / Decimal(days)
            average = daily
            estimate = daily * Decimal(Self.daysRemaining(in: now, now: now) - 1)
        }
        return MonthForecast(current: current, upcoming: upcomingRecurring(now: now),
                             estimatedSpending: estimate.map { max(0, $0) }, dailyAverage: average)
    }

    /// Solde prévu en fin de mois d'un compte (nil = compte par défaut) : solde actuel + récurrentes à venir.
    func projectedBalance(of account: Account? = nil, now: Date = .now) -> Decimal {
        let target = account ?? defaultAccount
        let upcoming = upcomingRecurring(now: now, accountID: target.id).reduce(Decimal(0)) { $0 + $1.amount }
        return balance(of: target) + upcoming
    }
}
