import SwiftUI

/// Montant arrondi à l'euro près si possible (« 120 € », « 12,50 € »).
func budgetEuros(_ value: Decimal) -> String {
    value.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...2)))
}

/// Ligne de budget : pastille, nom, barre de progression, « dépensé / budget ».
struct BudgetProgressRow: View {
    @Environment(\.theme) private var theme
    let status: BudgetStatus
    var month: Date = .now
    /// Version détaillée (Statistiques) : reste à dépenser et moyenne par jour.
    var detailed = false

    private var barColor: Color {
        switch status.state {
        case .ok: theme.color(for: status.category)
        case .warning: theme.warning
        case .exceeded: theme.negative
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing) {
            CategoryBadge(category: status.category)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.category.label)
                        .font(theme.bodyFont)
                        .foregroundStyle(status.state == .exceeded ? theme.negative : theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: theme.spacing)
                    Text("\(budgetEuros(status.spent)) / \(budgetEuros(status.budget))")
                        .font(theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(status.state == .exceeded ? theme.negative : theme.textSecondary)
                        .lineLimit(1)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2).fill(theme.surfaceSecondary)
                        RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2).fill(barColor)
                            .frame(width: geo.size.width * min(1, max(0, status.ratio)))
                    }
                }
                .frame(height: 5)
                if status.state == .exceeded {
                    Text("Dépassé de \(budgetEuros(status.overspent))")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.negative)
                } else if detailed {
                    Text(detailText)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detailText: String {
        var text = "Reste \(budgetEuros(status.remaining))"
        let days = BudgetStore.daysRemaining(in: month)
        if days > 0 {
            text += " · \(budgetEuros(status.remaining / Decimal(days))) / jour possible"
        }
        return text
    }
}

/// Carte « Budgets » : toutes les catégories budgétées, repliable au-delà de `limit`.
struct BudgetsCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date
    /// Nombre de lignes visibles avant « Voir tout » (nil = toutes).
    var limit: Int?
    var detailed = false
    @State private var expanded = false

    var body: some View {
        let statuses = store.budgetStatuses(month: month)
        if !statuses.isEmpty {
            let visible = (limit != nil && !expanded) ? Array(statuses.prefix(limit ?? 0)) : statuses
            Card {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    Text("Budgets")
                        .font(theme.titleFont)
                        .foregroundStyle(theme.textPrimary)
                    if detailed {
                        let totals = store.budgetTotals(month: month)
                        Text("Total : \(budgetEuros(totals.spent)) / \(budgetEuros(totals.budget))")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                    ForEach(visible) { BudgetProgressRow(status: $0, month: month, detailed: detailed) }
                    if let limit, statuses.count > limit {
                        Button(expanded ? "Réduire" : "Voir tout") {
                            withAnimation { expanded.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                    }
                }
            }
        }
    }
}
