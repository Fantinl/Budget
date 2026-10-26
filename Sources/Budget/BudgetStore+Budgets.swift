import Foundation

/// État d'un budget : < 80 % ok, 80–100 % attention, > 100 % dépassé.
enum BudgetState {
    case ok, warning, exceeded
}

/// Situation d'une catégorie budgétée sur un mois.
struct BudgetStatus: Identifiable {
    let category: Category
    let spent: Decimal
    /// Budget prévu pour ce mois (budget du mois s'il existe, sinon budget par défaut).
    let planned: Decimal
    /// Report des mois précédents de l'année (positif = reste, négatif = dépassement), 0 sans report.
    var carryOver: Decimal = 0

    init(category: Category, spent: Decimal, planned: Decimal, carryOver: Decimal = 0) {
        self.category = category
        self.spent = spent
        self.planned = planned
        self.carryOver = carryOver
    }

    var id: String { category.id }
    /// Montant disponible ce mois : budget prévu + report (jamais négatif).
    var budget: Decimal { max(0, planned + carryOver) }
    /// Reste à dépenser (négatif si dépassé).
    var remaining: Decimal { budget - spent }
    var ratio: Double {
        if budget > 0 { return spent.doubleValue / budget.doubleValue }
        return spent > 0 ? 2 : 0   // report qui a tout absorbé : la moindre dépense dépasse
    }
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

/// Dépenses (hors virements) par catégorie et par mois, calculées en une seule passe sur les opérations.
struct MonthlySpending {
    /// Identifiant de catégorie → clé de mois → montant dépensé.
    private var amounts: [String: [String: Decimal]] = [:]
    /// Clés des mois ayant au moins une opération (dépense, revenu ou virement).
    private(set) var monthsWithData: Set<String> = []

    init(transactions: [Transaction], from start: Date, to end: Date) {
        for t in transactions where t.date >= start && t.date < end {
            let key = BudgetStore.monthKey(t.date)
            monthsWithData.insert(key)
            if t.isSpending { amounts[t.categoryID, default: [:]][key, default: 0] += t.amount }
        }
    }

    func spent(_ categoryID: String, month: Date) -> Decimal {
        amounts[categoryID]?[BudgetStore.monthKey(month)] ?? 0
    }

    func hasData(_ month: Date) -> Bool { monthsWithData.contains(BudgetStore.monthKey(month)) }
}

// Budgets mensuels par catégorie. Calculés sur tous les comptes, virements exclus.
extension BudgetStore {
    /// Clé d'un mois (« 2026-10 ») pour les budgets propres à un mois.
    nonisolated static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// Dépenses (hors virements) d'une catégorie sur le mois de `month`, tous comptes.
    func spent(in category: Category, month: Date) -> Decimal {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return 0 }
        return transactions.reduce(0) { total, t in
            t.isSpending && t.categoryID == category.id && t.date >= interval.start && t.date < interval.end ? total + t.amount : total
        }
    }

    /// Budget prévu d'une catégorie pour un mois : budget de ce mois s'il existe, sinon budget par défaut.
    func plannedBudget(for category: Category, month: Date) -> Decimal {
        guard category.kind == .expense else { return 0 }
        if let override = category.budgetOverrides?[Self.monthKey(month)] { return max(0, override) }
        return max(0, category.monthlyBudget ?? 0)
    }

    /// Vrai si la catégorie a un budget propre à ce mois (différent du budget par défaut).
    func hasBudgetOverride(for category: Category, month: Date) -> Bool {
        category.budgetOverrides?[Self.monthKey(month)] != nil
    }

    /// Catégories de dépense ayant un budget > 0 ce mois-ci (visibles ou non, tant qu'un budget existe).
    func budgetedCategories(month: Date) -> [Category] {
        categories.filter { plannedBudget(for: $0, month: month) > 0 }
    }

    /// Catégories budgétées pour le mois en cours.
    var budgetedCategories: [Category] { budgetedCategories(month: .now) }

    /// Premier mois compté dans l'équilibre de l'année de `month` : janvier, ou le premier mois
    /// avec des opérations s'il est plus tard (les mois d'avant l'utilisation de l'app ne comptent pas).
    func balanceStart(forYearOf month: Date) -> Date {
        let cal = Calendar.current
        let yearStart = cal.dateInterval(of: .year, for: month)?.start ?? month.startOfMonth
        guard let first = transactions.lazy.map(\.date).min() else { return yearStart }
        return max(yearStart, first.startOfMonth)
    }

    /// Report d'une catégorie au début de `month` : somme (budget prévu − dépensé) des mois précédents
    /// de la même année. 0 si le report n'est pas activé.
    func carryOver(for category: Category, month: Date, spending: MonthlySpending? = nil) -> Decimal {
        guard category.budgetRollover == true else { return 0 }
        let monthStart = month.startOfMonth
        var cursor = balanceStart(forYearOf: monthStart)
        guard cursor < monthStart else { return 0 }
        let index = spending ?? MonthlySpending(transactions: transactions, from: cursor, to: monthStart)
        var total: Decimal = 0
        while cursor < monthStart {
            total += plannedBudget(for: category, month: cursor) - index.spent(category.id, month: cursor)
            cursor = cursor.addingMonths(1)
        }
        return total
    }

    func budgetStatus(for category: Category, month: Date) -> BudgetStatus? {
        budgetStatus(for: category, month: month, spending: yearSpending(through: month))
    }

    private func budgetStatus(for category: Category, month: Date, spending: MonthlySpending) -> BudgetStatus? {
        let planned = plannedBudget(for: category, month: month)
        guard planned > 0 else { return nil }
        return BudgetStatus(category: category, spent: spending.spent(category.id, month: month), planned: planned,
                            carryOver: carryOver(for: category, month: month, spending: spending))
    }

    /// Index des dépenses du début de l'année de `month` jusqu'à la fin de ce mois.
    func yearSpending(through month: Date) -> MonthlySpending {
        let start = balanceStart(forYearOf: month)
        let end = month.startOfMonth.addingMonths(1)
        return MonthlySpending(transactions: transactions, from: min(start, month.startOfMonth), to: end)
    }

    /// Statuts de toutes les catégories budgétées, du plus consommé au moins consommé.
    func budgetStatuses(month: Date) -> [BudgetStatus] {
        let spending = yearSpending(through: month)
        return budgetedCategories(month: month)
            .compactMap { budgetStatus(for: $0, month: month, spending: spending) }
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

    /// Part du mois écoulée (0 pour un mois futur, 1 pour un mois passé), aujourd'hui compris.
    nonisolated static func elapsedFraction(of month: Date, now: Date = .now) -> Double {
        let total = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 30
        return Double(total - daysRemaining(in: month, now: now) + (isCurrentMonth(month, now: now) ? 1 : 0)) / Double(total)
    }

    nonisolated static func isCurrentMonth(_ month: Date, now: Date = .now) -> Bool {
        Calendar.current.isDate(month, equalTo: now, toGranularity: .month)
    }

    // MARK: - Modifications

    /// Fixe (ou retire, avec nil) le budget mensuel par défaut d'une catégorie.
    func setMonthlyBudget(_ budget: Decimal?, for category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        registerUndo("Modifier le budget")
        categories[index].monthlyBudget = (budget ?? 0) > 0 ? budget : nil
        saveSettings()
    }

    /// Budget d'une catégorie pour un seul mois. nil = revenir au budget par défaut ; 0 = pas de budget ce mois-là.
    func setBudgetOverride(_ budget: Decimal?, for category: Category, month: Date) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        registerUndo("Modifier le budget du mois")
        var overrides = categories[index].budgetOverrides ?? [:]
        let key = Self.monthKey(month)
        if let budget, max(0, budget) != (categories[index].monthlyBudget ?? 0) {
            overrides[key] = max(0, budget)
        } else {
            overrides[key] = nil   // identique au budget par défaut : inutile de le garder
        }
        categories[index].budgetOverrides = overrides.isEmpty ? nil : overrides
        saveSettings()
    }

    /// Retire tout budget de la catégorie : par défaut, propres à un mois et report.
    func removeBudget(for category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        registerUndo("Retirer le budget")
        categories[index].monthlyBudget = nil
        categories[index].budgetOverrides = nil
        categories[index].budgetRollover = nil
        saveSettings()
    }

    /// Active ou coupe le report du reste / dépassement d'un mois sur l'autre.
    func setBudgetRollover(_ enabled: Bool, for category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        registerUndo(enabled ? "Activer le report" : "Désactiver le report")
        categories[index].budgetRollover = enabled ? true : nil
        saveSettings()
    }

    /// Objectif d'épargne et revenus prévus.
    func setBudgetPlan(_ plan: BudgetPlan) {
        guard plan != budgetPlan else { return }
        registerUndo("Modifier la planification")
        budgetPlan = plan
        saveSettings()
    }
}
