import SwiftUI

/// Synthèse du mois : « Il te reste X € à dépenser », jauge et rythme possible par jour.
struct BudgetSummaryCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date

    private var isCurrent: Bool { BudgetStore.isCurrentMonth(month) }
    private var isPast: Bool { month.startOfMonth < Date.now.startOfMonth }

    /// Couleur de la jauge, mêmes seuils que les enveloppes : dépassé (> 100 %), à surveiller (≥ 80 %) ou normal.
    private func tint(_ totals: BudgetTotals) -> Color {
        if totals.ratio > 1 { return theme.negative }
        if totals.ratio >= 0.8 { return theme.warning }
        return theme.accent
    }

    var body: some View {
        let statuses = store.budgetStatuses(month: month)
        let hasBudget = !statuses.isEmpty
        let totals = store.budgetTotals(month: month)
        Card {
            if hasBudget {
                content(totals, statuses: statuses)
            } else {
                emptyState
            }
        }
    }

    // MARK: - État vide

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            Label("Budget du mois", systemImage: "chart.pie")
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)
            Text("Aucun budget n'est fixé ce mois-ci. Fixe un budget par catégorie plus bas, ou applique les suggestions pour démarrer à partir de tes dépenses habituelles.")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
            AddBudgetMenu(month: month)
        }
    }

    // MARK: - Contenu

    private func content(_ totals: BudgetTotals, statuses: [BudgetStatus]) -> some View {
        let remaining = totals.remaining
        let title = remaining >= 0 ? "Il te reste \(wholeEuros(remaining)) à dépenser"
                                   : "Budget dépassé de \(wholeEuros(-remaining))"
        return VStack(alignment: .leading, spacing: theme.spacing) {
            Text(title)
                .font(theme.largeAmountFont)
                .foregroundStyle(remaining >= 0 ? theme.textPrimary : theme.negative)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            gauge(totals)
            Text("Dépensé \(wholeEuros(totals.spent)) sur \(wholeEuros(totals.budget))")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
            if let note = note(statuses) {
                Text(note)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func gauge(_ totals: BudgetTotals) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.surfaceSecondary)
                Capsule().fill(tint(totals))
                    .frame(width: geo.size.width * min(1, max(0, totals.ratio)))
            }
        }
        .frame(height: 10)
    }

    /// « ≈ C € par jour pendant N jours », « Mois terminé » ou « Mois à venir ».
    /// Calculée sur le reste des enveloppes non fixes seulement.
    private func note(_ statuses: [BudgetStatus]) -> String? {
        if isPast { return "Mois terminé" }
        if !isCurrent { return "Mois à venir" }
        let days = BudgetStore.daysRemaining(in: month)
        let flexible = statuses.filter { !$0.isFixed }
        let remaining = flexible.reduce(Decimal(0)) { $0 + $1.budget } - flexible.reduce(Decimal(0)) { $0 + $1.spent }
        guard remaining > 0, days > 0 else { return nil }
        let perDay = wholeEuros(remaining / Decimal(days))
        return "≈ \(perDay) par jour pendant \(days) \(days == 1 ? "jour" : "jours")"
    }
}
