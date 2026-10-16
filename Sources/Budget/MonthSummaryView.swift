import SwiftUI

struct MonthSummaryView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    let transactions: [Transaction]
    /// Mois affiché ; par défaut déduit des opérations (sinon le mois en cours).
    var month: Date? = nil

    private var displayedMonth: Date {
        (month ?? transactions.first?.date ?? .now).startOfMonth
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: .now, toGranularity: .month)
    }

    private var expenses: Decimal {
        transactions.filter(\.isSpending).reduce(0) { $0 + $1.amount }
    }

    private var income: Decimal {
        transactions.filter(\.isEarning).reduce(0) { $0 + $1.amount }
    }

    /// Total des dépenses par catégorie, de la plus grosse à la plus petite.
    private var expensesByCategory: [(category: Category, total: Decimal)] {
        Dictionary(grouping: transactions.filter(\.isSpending), by: \.categoryID)
            .map { (store.category(id: $0.key), $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            heroCard
            BudgetsCard(month: displayedMonth, limit: 4)
        }
    }

    private var heroCard: some View {
        let balance = income - expenses
        return HeroCard {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Solde du mois")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.heroTextSecondary)

                Text(balance.euros)
                    .font(theme.largeAmountFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.heroTintsBalance ? (balance >= 0 ? theme.positive : theme.negative) : theme.heroTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                HStack(spacing: theme.padding) {
                    stat("Dépenses", expenses)
                    stat("Revenus", income)
                }

                if !expensesByCategory.isEmpty {
                    distributionBar
                }

                if isCurrentMonth {
                    let projected = store.monthForecast().projected
                    HStack(spacing: 6) {
                        Text("Fin de mois prévue")
                            .foregroundStyle(theme.heroTextSecondary)
                        Text((projected > 0 ? "+" : "") + projected.euros)
                            .monospacedDigit()
                            .foregroundStyle(theme.heroTextPrimary)
                    }
                    .font(theme.captionFont)
                    .lineLimit(1)
                }
            }
        }
    }

    /// Barre fine : un segment par catégorie, proportionnel aux dépenses.
    private var distributionBar: some View {
        let total = expensesByCategory.reduce(Decimal(0)) { $0 + $1.total }.doubleValue
        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(expensesByCategory, id: \.category.id) { item in
                    Rectangle()
                        .fill(theme.color(for: item.category))
                        .frame(width: max(2, geo.size.width * item.total.doubleValue / max(total, 1)))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipShape(.rect(cornerRadius: theme.smallCornerRadius / 2))
        }
        .frame(height: 6)
        .background(theme.surfaceSecondary, in: .rect(cornerRadius: theme.smallCornerRadius / 2))
    }

    private func stat(_ title: String, _ value: Decimal) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(theme.heroTextSecondary)
            Text(value.euros)
                .monospacedDigit()
                .foregroundStyle(theme.heroTextPrimary)
        }
        .font(theme.captionFont)
        .lineLimit(1)
    }
}
