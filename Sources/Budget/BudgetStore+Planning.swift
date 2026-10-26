import Foundation

// Page Budget : plan du mois, équilibre de l'année, projection de fin de mois et suggestions.

/// Origine des revenus prévus du mois.
enum PlannedIncomeSource {
    /// Saisis à la main (`BudgetPlan.expectedIncome`).
    case manual
    /// Revenus récurrents tombant dans le mois.
    case recurring
    /// Moyenne des revenus des 3 mois précédents.
    case average
    /// Aucune information.
    case none

    var label: String {
        switch self {
        case .manual: "Saisis à la main"
        case .recurring: "D'après tes revenus récurrents"
        case .average: "Moyenne des 3 derniers mois"
        case .none: "Aucun revenu connu"
        }
    }
}

/// Charge fixe du mois : une échéance de récurrente dont la catégorie n'a pas de budget.
struct PlannedCharge: Identifiable {
    let id = UUID()
    let name: String
    let categoryID: String
    let date: Date
    let amount: Decimal
}

/// Plan d'un mois : revenus prévus − charges fixes − enveloppes − épargne = reste à répartir.
struct MonthPlan {
    let month: Date
    let expectedIncome: Decimal
    let incomeSource: PlannedIncomeSource
    /// Charges fixes (récurrentes de dépense hors catégories budgétées), triées par date.
    let fixedCharges: [PlannedCharge]
    /// Somme des budgets disponibles des catégories (report compris).
    let envelopes: Decimal
    let savingsGoal: Decimal
    /// Réalisé : revenus et dépenses du mois (hors virements).
    let actualIncome: Decimal
    let actualSpent: Decimal
    /// Dépenses du mois dans des catégories sans budget (charges fixes comprises).
    let unbudgetedSpent: Decimal

    var fixedTotal: Decimal { fixedCharges.reduce(0) { $0 + $1.amount } }
    /// Reste à répartir (négatif = plan déficitaire).
    var unallocated: Decimal { expectedIncome - fixedTotal - envelopes - savingsGoal }
    /// Épargne réelle du mois à ce jour.
    var actualSavings: Decimal { actualIncome - actualSpent }
}

/// Une case de l'équilibre annuel : une catégorie (ou le total) sur un mois.
struct AnnualBudgetCell: Identifiable {
    let month: Date
    let planned: Decimal
    let spent: Decimal
    /// Mois compté dans l'équilibre (écoulé ou en cours, et après le début d'utilisation de l'app).
    let isCounted: Bool
    let isCurrent: Bool
    /// Mois pas encore commencé.
    let isFuture: Bool

    var id: Date { month }
    /// Écart du mois : positif = économie, négatif = dépassement.
    var difference: Decimal { planned - spent }
}

/// Tendance de l'année pour une catégorie.
enum AnnualBudgetTrend {
    /// Aucun mois dépassé.
    case onTrack
    /// Au moins un mois dépassé, mais le cumul est revenu à l'équilibre.
    case recovered
    /// Le cumul de l'année est négatif : il reste un dépassement à rattraper.
    case behind

    var label: String {
        switch self {
        case .onTrack: "Dans les clous"
        case .recovered: "Rattrapé"
        case .behind: "À rattraper"
        }
    }
}

/// Ligne de l'équilibre annuel (une catégorie budgétée, ou le total si `category` est nil).
struct AnnualBudgetRow: Identifiable {
    let category: Category?
    /// Les 12 mois de l'année.
    let cells: [AnnualBudgetCell]

    var id: String { category?.id ?? "total" }
    var counted: [AnnualBudgetCell] { cells.filter(\.isCounted) }
    /// Cumul (budget − dépensé) des mois comptés : positif = d'avance, négatif = en retard.
    var balance: Decimal { counted.reduce(0) { $0 + $1.difference } }
    var plannedToDate: Decimal { counted.reduce(0) { $0 + $1.planned } }
    var spentToDate: Decimal { counted.reduce(0) { $0 + $1.spent } }
    /// Budget de l'année entière (mois comptés + mois à venir).
    var plannedYear: Decimal { cells.filter { $0.isCounted || $0.isFuture }.reduce(0) { $0 + $1.planned } }
    /// Mois dépassés parmi les mois comptés.
    var exceededMonths: Int { counted.filter { $0.difference < 0 }.count }

    var trend: AnnualBudgetTrend {
        if balance < 0 { return .behind }
        return exceededMonths > 0 ? .recovered : .onTrack
    }

    /// Cumul à la fin de chaque mois compté (pour la courbe).
    var runningBalance: [(month: Date, balance: Decimal)] {
        var total: Decimal = 0
        return counted.map { cell in
            total += cell.difference
            return (cell.month, total)
        }
    }

    /// Budget mensuel moyen à respecter sur les mois restants pour finir l'année à l'équilibre.
    /// nil s'il ne reste aucun mois ou si la catégorie est déjà à l'équilibre.
    var catchUpPerMonth: Decimal? {
        let remaining = cells.filter(\.isFuture)
        guard balance < 0, !remaining.isEmpty else { return nil }
        let plannedRemaining = remaining.reduce(Decimal(0)) { $0 + $1.planned }
        return max(0, (plannedRemaining + balance) / Decimal(remaining.count))
    }
}

/// Équilibre de l'année : chaque catégorie budgétée, mois par mois, et le total.
struct AnnualBudgetBalance {
    let year: Date
    let rows: [AnnualBudgetRow]
    let total: AnnualBudgetRow
}

/// Proposition de budget tirée des dépenses des derniers mois.
struct BudgetSuggestion: Identifiable {
    enum Reason {
        /// Catégorie sans budget mais avec des dépenses régulières.
        case noBudget
        /// Budget dépassé la plupart des mois.
        case tooLow
        /// Budget largement sous-utilisé.
        case tooHigh

        var label: String {
            switch self {
            case .noBudget: "Pas encore de budget"
            case .tooLow: "Souvent dépassé"
            case .tooHigh: "Largement sous-utilisé"
            }
        }
    }

    let category: Category
    let reason: Reason
    /// Budget par défaut actuel (nil = aucun).
    let current: Decimal?
    /// Moyenne mensuelle des mois analysés.
    let average: Decimal
    let suggested: Decimal
    let monthsAnalysed: Int

    var id: String { category.id }
}

extension BudgetStore {
    // MARK: - Plan du mois

    func monthPlan(month: Date, now: Date = .now) -> MonthPlan {
        let cal = Calendar.current
        let monthStart = month.startOfMonth
        let lastDay = cal.date(byAdding: .day, value: -1, to: monthStart.addingMonths(1)) ?? monthStart
        let monthTransactions = transactions(inMonthOf: monthStart)
        let statuses = budgetStatuses(month: monthStart)
        let budgeted = Set(statuses.map(\.id))

        var charges: [PlannedCharge] = []
        var recurringIncome: Decimal = 0
        for operation in recurringOperations where operation.isActive {
            let dates = occurrences(of: operation, from: monthStart, to: lastDay)
            switch operation.kind {
            case .income:
                recurringIncome += operation.amount * Decimal(dates.count)
            case .expense where !budgeted.contains(operation.categoryID):
                charges += dates.map { PlannedCharge(name: operation.name, categoryID: operation.categoryID,
                                                     date: $0, amount: operation.amount) }
            case .expense:
                break   // déjà compté dans l'enveloppe de sa catégorie
            }
        }

        let income: Decimal
        let source: PlannedIncomeSource
        if let manual = budgetPlan.expectedIncome, manual > 0 {
            (income, source) = (manual, .manual)
        } else if recurringIncome > 0 {
            (income, source) = (recurringIncome, .recurring)
        } else if let average = averageIncome(before: monthStart) {
            (income, source) = (average, .average)
        } else {
            (income, source) = (0, .none)
        }

        let actualIncome = monthTransactions.filter(\.isEarning).reduce(Decimal(0)) { $0 + $1.amount }
        let spending = monthTransactions.filter(\.isSpending)
        return MonthPlan(month: monthStart, expectedIncome: income, incomeSource: source,
                         fixedCharges: charges.sorted { $0.date < $1.date },
                         envelopes: statuses.reduce(0) { $0 + $1.budget },
                         savingsGoal: max(0, budgetPlan.savingsGoal ?? 0),
                         actualIncome: actualIncome,
                         actualSpent: spending.reduce(0) { $0 + $1.amount },
                         unbudgetedSpent: spending.filter { !budgeted.contains($0.categoryID) }.reduce(0) { $0 + $1.amount })
    }

    /// Moyenne des revenus des 3 mois précédant `month` qui en ont, nil s'il n'y en a aucun.
    func averageIncome(before month: Date) -> Decimal? {
        let totals = (1...3).map { back in
            transactions(inMonthOf: month.addingMonths(-back)).filter(\.isEarning).reduce(Decimal(0)) { $0 + $1.amount }
        }.filter { $0 > 0 }
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Decimal(totals.count)
    }

    // MARK: - Équilibre de l'année

    func annualBudgetBalance(year: Date, now: Date = .now) -> AnnualBudgetBalance {
        let cal = Calendar.current
        let yearStart = cal.dateInterval(of: .year, for: year)?.start ?? year.startOfMonth
        let months = (0..<12).map { yearStart.addingMonths($0) }
        let firstCounted = balanceStart(forYearOf: yearStart)
        let currentMonth = now.startOfMonth
        let spending = MonthlySpending(transactions: transactions, from: yearStart, to: yearStart.addingMonths(12))

        let categoriesInYear = categories.filter { category in
            category.kind == .expense && months.contains { plannedBudget(for: category, month: $0) > 0 }
        }
        let rows = categoriesInYear.map { category in
            AnnualBudgetRow(category: category, cells: months.map { month in
                AnnualBudgetCell(month: month, planned: plannedBudget(for: category, month: month),
                                 spent: spending.spent(category.id, month: month),
                                 isCounted: month >= firstCounted && month <= currentMonth,
                                 isCurrent: month == currentMonth, isFuture: month > currentMonth)
            })
        }
        .sorted { $0.balance < $1.balance }   // les plus en retard d'abord

        let totalCells = months.enumerated().map { index, month in
            AnnualBudgetCell(month: month,
                             planned: rows.reduce(0) { $0 + $1.cells[index].planned },
                             spent: rows.reduce(0) { $0 + $1.cells[index].spent },
                             isCounted: month >= firstCounted && month <= currentMonth,
                             isCurrent: month == currentMonth, isFuture: month > currentMonth)
        }
        return AnnualBudgetBalance(year: yearStart, rows: rows, total: AnnualBudgetRow(category: nil, cells: totalCells))
    }

    // MARK: - Projection de fin de mois

    /// Dépense estimée d'une catégorie en fin de mois (mois en cours seulement) :
    /// déjà dépensé + rythme des dépenses ponctuelles sur les jours restants + récurrentes à venir.
    func projectedSpending(for category: Category, month: Date, now: Date = .now) -> Decimal? {
        guard Self.isCurrentMonth(month, now: now) else { return nil }
        let cal = Calendar.current
        let spending = transactions(inMonthOf: month).filter { $0.isSpending && $0.categoryID == category.id }
        let spent = spending.reduce(Decimal(0)) { $0 + $1.amount }
        let elapsedDays = cal.component(.day, from: now)
        let remainingDays = Self.daysRemaining(in: month, now: now) - 1   // aujourd'hui est déjà compté
        let oneOff = spending.filter { $0.recurringID == nil }.reduce(Decimal(0)) { $0 + $1.amount }
        let pace = elapsedDays > 0 ? oneOff / Decimal(elapsedDays) * Decimal(max(0, remainingDays)) : 0

        var upcoming: Decimal = 0
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
           let lastDay = cal.date(byAdding: .day, value: -1, to: month.startOfMonth.addingMonths(1)), tomorrow <= lastDay {
            for operation in recurringOperations where operation.isActive && operation.kind == .expense
                && operation.categoryID == category.id {
                upcoming += operation.amount * Decimal(occurrences(of: operation, from: tomorrow, to: lastDay).count)
            }
        }
        return spent + pace + upcoming
    }

    // MARK: - Suggestions

    /// Budgets proposés d'après les 3 mois complets précédents (ceux qui ont des opérations).
    func budgetSuggestions(now: Date = .now) -> [BudgetSuggestion] {
        let current = now.startOfMonth
        let months = (1...3).map { current.addingMonths(-$0) }
        let spending = MonthlySpending(transactions: transactions, from: current.addingMonths(-3), to: current)
        let analysed = months.filter { spending.hasData($0) }
        guard !analysed.isEmpty else { return [] }

        return categories.compactMap { category -> BudgetSuggestion? in
            guard category.kind == .expense, !category.isHidden else { return nil }
            let amounts = analysed.map { spending.spent(category.id, month: $0) }
            let average = amounts.reduce(0, +) / Decimal(analysed.count)
            let budget = category.monthlyBudget ?? 0
            let reason: BudgetSuggestion.Reason
            if budget <= 0 {
                guard average >= 10 else { return nil }
                reason = .noBudget
            } else if analysed.count >= 2, amounts.filter({ $0 > budget }).count * 2 > analysed.count, average > budget * 1.05 {
                reason = .tooLow
            } else if analysed.count >= 2, average < budget * 0.6 {
                reason = .tooHigh
            } else {
                return nil
            }
            let suggested = Self.roundedBudget(average)
            guard suggested > 0, suggested != budget else { return nil }
            return BudgetSuggestion(category: category, reason: reason, current: budget > 0 ? budget : nil,
                                    average: average, suggested: suggested, monthsAnalysed: analysed.count)
        }
        .sorted { $0.average > $1.average }
    }

    /// Arrondi « lisible » vers le haut : à 5 € sous 100 €, à 10 € au-delà.
    nonisolated static func roundedBudget(_ value: Decimal) -> Decimal {
        guard value > 0 else { return 0 }
        let step: Double = value < 100 ? 5 : 10
        return Decimal((value.doubleValue / step).rounded(.up) * step)
    }

    /// Applique une suggestion comme nouveau budget par défaut.
    func apply(_ suggestion: BudgetSuggestion) {
        setMonthlyBudget(suggestion.suggested, for: suggestion.category)
    }
}
