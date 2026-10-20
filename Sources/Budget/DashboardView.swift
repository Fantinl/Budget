import SwiftUI

/// Page d'accueil : l'essentiel du budget en cartes cliquables.
struct DashboardView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    /// Demande l'affichage d'une autre page.
    var navigate: (SidebarItem) -> Void = { _ in }
    @State private var draft: Draft?

    var body: some View {
        let summary = DashboardSummary(store: store)
        ScrollView {
            VStack(spacing: theme.spacing) {
                availableCard(summary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: theme.spacing, alignment: .top)],
                          spacing: theme.spacing) {
                    monthCard(summary)
                    if summary.izly != nil { izlyCard(summary) }
                    savingsCard(summary)
                    wealthCard(summary)
                    if !summary.topBudgets.isEmpty { budgetsCard(summary) }
                    upcomingCard(summary)
                    latestCard(summary)
                }
            }
            .padding(theme.padding)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Tableau de bord")
        .sheet(item: $draft) { OperationEditor(draft: $0) }
    }

    // MARK: - Cartes

    private func availableCard(_ s: DashboardSummary) -> some View {
        Button { navigate(.accounts) } label: {
            HeroCard {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    Text("Argent disponible")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.heroTextSecondary)
                    Text(s.available.euros)
                        .font(theme.largeAmountFont)
                        .foregroundStyle(theme.heroTextPrimary)
                    if s.currentAccounts.count > 1 {
                        VStack(spacing: 4) {
                            ForEach(s.currentAccounts, id: \.account.id) { item in
                                HStack {
                                    Text(item.account.name)
                                    Spacer()
                                    Text(item.balance.euros).monospacedDigit()
                                }
                                .font(theme.captionFont)
                                .foregroundStyle(theme.heroTextSecondary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func monthCard(_ s: DashboardSummary) -> some View {
        tappable(.stats) {
            title("Reste ce mois-ci")
            Text(s.monthRemaining.euros)
                .font(theme.largeAmountFont)
                .foregroundStyle(s.monthRemaining >= 0 ? theme.positive : theme.negative)
            line("Revenus", s.monthIncome.euros, color: theme.positive)
            line("Dépenses", s.monthSpent.euros)
            line("Fin de mois prévue", s.forecast.euros,
                 color: s.forecast >= 0 ? theme.textPrimary : theme.negative)
            if let totals = s.budgetTotals {
                line("Budgets restants", budgetEuros(totals.remaining),
                     color: totals.remaining >= 0 ? theme.textPrimary : theme.negative)
            }
        }
    }

    @ViewBuilder
    private func izlyCard(_ s: DashboardSummary) -> some View {
        if let izly = s.izly {
            tappable(.accounts) {
                title("Izly")
                Text(izly.balance.euros)
                    .font(theme.largeAmountFont)
                    .foregroundStyle(theme.textPrimary)
                Text("≈ \(izly.meals) repas restants")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
                if s.izlyIsLow {
                    Label("Pense à recharger", systemImage: "exclamationmark.circle")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.warning)
                }
            }
        }
    }

    private func savingsCard(_ s: DashboardSummary) -> some View {
        tappable(.accounts) {
            title("Épargne et placements")
            Text(s.savings.euros)
                .font(theme.largeAmountFont)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private func wealthCard(_ s: DashboardSummary) -> some View {
        tappable(.accounts) {
            title("Patrimoine total")
            Text(s.wealth.euros)
                .font(theme.largeAmountFont)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private func budgetsCard(_ s: DashboardSummary) -> some View {
        tappable(.stats) {
            title("Budgets")
            ForEach(s.topBudgets) { BudgetProgressRow(status: $0) }
        }
    }

    private func upcomingCard(_ s: DashboardSummary) -> some View {
        tappable(.accounts) {
            title("À venir")
            if s.upcoming.isEmpty {
                Text("Rien de prévu sous 30 jours.")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
            } else {
                ForEach(s.upcoming) { item in
                    HStack(spacing: theme.spacing) {
                        Text(item.date.formatted(Date.FormatStyle().day().month(.abbreviated)
                            .locale(Locale(identifier: "fr_FR"))))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 56, alignment: .leading)
                        Text(item.name)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: theme.spacing)
                        Text(item.amount.euros)
                            .font(theme.amountFont)
                            .monospacedDigit()
                            .foregroundStyle(item.amount >= 0 ? theme.positive : theme.textPrimary)
                    }
                }
            }
        }
    }

    private func latestCard(_ s: DashboardSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Button { navigate(.operations) } label: {
                    HStack {
                        title("Dernières opérations")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s.latest.isEmpty {
                    Text("Aucune opération.")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(s.latest) { t in
                    Button { draft = Draft(transaction: t, isNew: false) } label: {
                        TransactionRow(transaction: t).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Éléments communs

    private func title(_ text: String) -> some View {
        Text(text)
            .font(theme.captionFont)
            .foregroundStyle(theme.textSecondary)
    }

    private func line(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value)
                .font(theme.amountFont)
                .monospacedDigit()
                .foregroundStyle(color ?? theme.textPrimary)
        }
    }

    /// Carte entière cliquable vers une page.
    private func tappable<Content: View>(_ target: SidebarItem,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        Button { navigate(target) } label: {
            Card {
                VStack(alignment: .leading, spacing: theme.spacing) { content() }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
