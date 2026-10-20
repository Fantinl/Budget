import Foundation

/// Chiffres du tableau de bord (sans SwiftUI, testable).
struct DashboardSummary {
    /// Comptes courants actifs et leur solde.
    let currentAccounts: [(account: Account, balance: Decimal)]
    let available: Decimal
    let monthIncome: Decimal
    let monthSpent: Decimal
    let forecast: Decimal
    let budgetTotals: BudgetTotals?
    let topBudgets: [BudgetStatus]
    /// Compte Izly actif, son solde, le prix du repas et le nombre de repas restants.
    let izly: (account: Account, balance: Decimal, mealPrice: Decimal, meals: Int)?
    let savings: Decimal
    let wealth: Decimal
    let upcoming: [UpcomingRecurring]
    let latest: [Transaction]

    /// Sous cette limite, on invite à recharger Izly.
    static let lowMealThreshold = 5

    var monthRemaining: Decimal { monthIncome - monthSpent }
    var izlyIsLow: Bool { (izly?.meals ?? Int.max) < Self.lowMealThreshold }

    @MainActor
    init(store: BudgetStore, now: Date = .now) {
        let active = store.activeAccounts
        currentAccounts = active.filter { $0.kind.family == .current }
            .map { ($0, store.balance(of: $0)) }
        available = currentAccounts.reduce(0) { $0 + $1.balance }

        let month = store.transactions(inMonthOf: now)
        monthIncome = month.filter(\.isEarning).reduce(0) { $0 + $1.amount }
        monthSpent = month.filter(\.isSpending).reduce(0) { $0 + $1.amount }
        forecast = store.monthForecast(now: now).projected

        if store.budgetedCategories.isEmpty {
            budgetTotals = nil
            topBudgets = []
        } else {
            budgetTotals = store.budgetTotals(month: now)
            topBudgets = Array(store.budgetStatuses(month: now).prefix(3))
        }

        if let account = active.first(where: { $0.kind == .izly }) {
            let balance = store.balance(of: account)
            let configured = account.mealPlan?.price ?? StudentProfile.defaultMealPrice
            let price = configured > 0 ? configured : StudentProfile.defaultMealPrice
            let count = balance > 0 ? NSDecimalNumber(decimal: balance / price).intValue : 0
            izly = (account, balance, price, count)
        } else {
            izly = nil
        }

        savings = active.filter { $0.kind.family == .savings || $0.kind.family == .investment }
            .reduce(0) { $0 + store.value(of: $1) }
        wealth = store.totalBalance()

        // Récurrentes des 30 prochains jours (à partir de demain)
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let limit = cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: now)) ?? now
        var coming: [UpcomingRecurring] = []
        for operation in store.recurringOperations where operation.isActive {
            let signed = operation.kind == .expense ? -operation.amount : operation.amount
            for date in store.occurrences(of: operation, from: tomorrow, to: limit) {
                coming.append(UpcomingRecurring(name: operation.name, date: date, amount: signed))
            }
        }
        upcoming = Array(coming.sorted { $0.date < $1.date }.prefix(5))

        latest = Array(store.transactions.sorted { $0.date > $1.date }.prefix(5))
    }
}
