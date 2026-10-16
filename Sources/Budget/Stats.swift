import Foundation

// Logique de calcul des statistiques (sans SwiftUI).

enum StatsPeriod: String, CaseIterable, Identifiable {
    case month, threeMonths, year, all

    var id: Self { self }

    var label: String {
        switch self {
        case .month: "Mois"
        case .threeMonths: "3 mois"
        case .year: "Année"
        case .all: "Tout"
        }
    }

    /// Mois et année se parcourent avec précédent / suivant.
    var isNavigable: Bool { self == .month || self == .year }

    /// Nombre de mois d'une période fixe (nil pour « Tout »).
    var monthSpan: Int? {
        switch self {
        case .month: 1
        case .threeMonths: 3
        case .year: 12
        case .all: nil
        }
    }
}

struct CategoryTotal: Identifiable {
    let category: Category
    let amount: Decimal
    let share: Double
    var id: String { category.id }
}

struct MonthCategoryAmount: Identifiable {
    let month: Date
    let category: Category
    let amount: Double
    var id: String { "\(month.timeIntervalSince1970)-\(category.id)" }
}

struct MonthIncome: Identifiable {
    let month: Date
    let amount: Double
    var id: Date { month }
}

struct StatsSnapshot {
    let start: Date          // inclus
    let end: Date            // exclu
    let expenses: Decimal
    let income: Decimal
    let averagePerMonth: Decimal
    /// Variation des dépenses vs période précédente (0.12 = +12 %), nil si pas de référence.
    let expenseChange: Double?
    let categories: [CategoryTotal]
    let months: [Date]
    let monthlyExpenses: [MonthCategoryAmount]
    let monthlyIncome: [MonthIncome]
    let topExpenses: [Transaction]
    let hasData: Bool

    var balance: Decimal { income - expenses }

    init(transactions: [Transaction], period: StatsPeriod, offset: Int,
         category: (String) -> Category, now: Date = .now) {
        let cal = Calendar.current
        let currentMonth = now.startOfMonth

        // Bornes de la période
        var s: Date
        var e: Date
        switch period {
        case .month:
            s = currentMonth.addingMonths(offset)
            e = s.addingMonths(1)
        case .threeMonths:
            e = currentMonth.addingMonths(1)
            s = e.addingMonths(-3)
        case .year:
            let yearStart = cal.dateInterval(of: .year, for: now)?.start ?? currentMonth
            s = yearStart.addingMonths(12 * offset)
            e = s.addingMonths(12)
        case .all:
            let first = transactions.map(\.date).min()?.startOfMonth ?? currentMonth
            let last = transactions.map(\.date).max()?.startOfMonth ?? currentMonth
            s = min(first, currentMonth)
            e = max(last, currentMonth).addingMonths(1)
        }
        start = s
        end = e

        func inRange(_ t: Transaction, _ from: Date, _ to: Date) -> Bool {
            t.date >= from && t.date < to
        }
        let current = transactions.filter { inRange($0, s, e) }
        let spent = current.filter(\.isSpending)
        let earned = current.filter(\.isEarning)

        expenses = spent.reduce(0) { $0 + $1.amount }
        income = earned.reduce(0) { $0 + $1.amount }
        hasData = !current.isEmpty

        // Moyenne : on ne compte pas les mois futurs
        let elapsedEnd = min(e, currentMonth.addingMonths(1))
        let elapsed = cal.dateComponents([.month], from: s, to: elapsedEnd).month ?? 1
        averagePerMonth = expenses / Decimal(max(1, elapsed))

        // Période précédente, à date équivalente : si la période est en cours (ex. 1er–16 octobre),
        // on la compare au même nombre de jours de la précédente (1er–16 septembre).
        if let span = period.monthSpan {
            let cutoff = min(e, now)
            let prevEnd = cal.date(byAdding: .month, value: -span, to: cutoff) ?? s
            let prev = transactions.filter {
                $0.isSpending && inRange($0, s.addingMonths(-span), prevEnd)
            }.reduce(Decimal(0)) { $0 + $1.amount }
            expenseChange = prev > 0 ? ((expenses - prev) / prev).doubleValue : nil
        } else {
            expenseChange = nil
        }

        // Répartition par catégorie
        var byCategory: [String: Decimal] = [:]
        for t in spent { byCategory[t.categoryID, default: 0] += t.amount }
        let total = expenses.doubleValue
        categories = byCategory
            .map { CategoryTotal(category: category($0.key), amount: $0.value, share: total > 0 ? $0.value.doubleValue / total : 0) }
            .sorted { $0.amount > $1.amount }

        // Évolution mensuelle : 12 mois minimum, se terminant à la fin de la période
        let lastMonth = e.addingMonths(-1)
        let firstMonth = min(s, lastMonth.addingMonths(-11))
        var list: [Date] = []
        var m = firstMonth
        while m <= lastMonth {
            list.append(m)
            m = m.addingMonths(1)
        }
        months = list

        let chartStart = firstMonth
        var expenseBuckets: [Date: [String: Double]] = [:]
        var incomeBuckets: [Date: Double] = [:]
        for t in transactions where inRange(t, chartStart, lastMonth.addingMonths(1)) {
            let month = t.date.startOfMonth
            if t.isTransfer { continue }
            if t.kind == .expense {
                expenseBuckets[month, default: [:]][t.categoryID, default: 0] += t.amount.doubleValue
            } else {
                incomeBuckets[month, default: 0] += t.amount.doubleValue
            }
        }
        monthlyExpenses = list.flatMap { month in
            (expenseBuckets[month] ?? [:])
                .sorted { $0.key < $1.key }
                .map { MonthCategoryAmount(month: month, category: category($0.key), amount: $0.value) }
        }
        monthlyIncome = list.map { MonthIncome(month: $0, amount: incomeBuckets[$0] ?? 0) }

        topExpenses = Array(spent.sorted { $0.amount > $1.amount }.prefix(5))
    }
}
