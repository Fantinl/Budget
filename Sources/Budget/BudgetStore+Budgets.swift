import Foundation

/// État d'un budget : < 80 % ok, 80–100 % attention, > 100 % dépassé.
enum BudgetState {
    case ok, warning, exceeded
}

/// Situation d'une catégorie budgétée sur un mois.
struct BudgetStatus: Identifiable {
    let category: Category
    let spent: Decimal
    let budget: Decimal

    var id: String { category.id }
    /// Reste à dépenser (négatif si dépassé).
    var remaining: Decimal { budget - spent }
    var ratio: Double { budget > 0 ? spent.doubleValue / budget.doubleValue : 0 }
    var state: BudgetState {
        if ratio > 1 { return .exceeded }
        if ratio >= 0.8 { return .warning }
        return .ok
    }
    var overspent: Decimal { max(0, spent - budget) }
}

/// Totaux sur l'ensemble des catégories budgétées.
struct BudgetTotals {
    let spent: Decimal
    let budget: Decimal
    var remaining: Decimal { budget - spent }
    var ratio: Double { budget > 0 ? spent.doubleValue / budget.doubleValue : 0 }
}

// Budgets mensuels par catégorie. Calculés sur tous les comptes, virements exclus.
extension BudgetStore {
    /// Dépenses (hors virements) d'une catégorie sur le mois de `month`, tous comptes.
    func spent(in category: Category, month: Date) -> Decimal {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return 0 }
        return transactions.reduce(0) { total, t in
            t.isSpending && t.categoryID == category.id && interval.contains(t.date) ? total + t.amount : total
        }
    }

    /// Catégories de dépense ayant un budget > 0 (visibles ou non, tant qu'un budget existe).
    var budgetedCategories: [Category] {
        categories.filter { $0.kind == .expense && ($0.monthlyBudget ?? 0) > 0 }
    }

    func budgetStatus(for category: Category, month: Date) -> BudgetStatus? {
        guard category.kind == .expense, let budget = category.monthlyBudget, budget > 0 else { return nil }
        return BudgetStatus(category: category, spent: spent(in: category, month: month), budget: budget)
    }

    /// Statuts de toutes les catégories budgétées, du plus consommé au moins consommé.
    func budgetStatuses(month: Date) -> [BudgetStatus] {
        budgetedCategories
            .compactMap { budgetStatus(for: $0, month: month) }
            .sorted { $0.ratio > $1.ratio }
    }

    func budgetTotals(month: Date) -> BudgetTotals {
        let statuses = budgetStatuses(month: month)
        return BudgetTotals(spent: statuses.reduce(0) { $0 + $1.spent },
                            budget: statuses.reduce(0) { $0 + $1.budget })
    }

    /// Jours restants dans le mois, aujourd'hui compris (0 pour un mois passé, tout le mois pour un mois futur).
    nonisolated static func daysRemaining(in month: Date, now: Date = .now) -> Int {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return 0 }
        let total = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        if now < interval.start { return total }
        if now >= interval.end { return 0 }
        return max(0, total - cal.component(.day, from: now) + 1)
    }

    /// Fixe (ou retire, avec nil) le budget mensuel d'une catégorie.
    func setMonthlyBudget(_ budget: Decimal?, for category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        registerUndo("Modifier le budget")
        categories[index].monthlyBudget = (budget ?? 0) > 0 ? budget : nil
        saveSettings()
    }
}
