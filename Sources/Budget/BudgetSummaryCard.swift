import SwiftUI

/// Synthèse du mois : jauge dépensé / disponible, rythme, compteurs et projection de fin de mois.
struct BudgetSummaryCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date

    private enum Pace {
        case ahead, watch, exceeded

        var message: String {
            switch self {
            case .ahead: "Tu es en avance sur ton budget"
            case .watch: "Rythme à surveiller"
            case .exceeded: "Budget dépassé"
            }
        }

        var icon: String {
            switch self {
            case .ahead: "checkmark.circle.fill"
            case .watch: "exclamationmark.triangle.fill"
            case .exceeded: "xmark.octagon.fill"
            }
        }
    }

    private var isCurrent: Bool { BudgetStore.isCurrentMonth(month) }
    private var isPast: Bool { month.startOfMonth < Date.now.startOfMonth }

    private func color(for pace: Pace) -> Color {
        switch pace {
        case .ahead: theme.positive
        case .watch: theme.warning
        case .exceeded: theme.negative
        }
    }

    private func pace(_ totals: BudgetTotals) -> Pace {
        if totals.ratio > 1 { return .exceeded }
        return totals.ratio > BudgetStore.elapsedFraction(of: month) + 0.05 ? .watch : .ahead
    }

    var body: some View {
        let statuses = store.budgetStatuses(month: month)
        let totals = store.budgetTotals(month: month)
        Card {
            if statuses.isEmpty {
                emptyState
            } else {
                content(statuses: statuses, totals: totals)
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
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Contenu

    private func content(statuses: [BudgetStatus], totals: BudgetTotals) -> some View {
        let state = pace(totals)
        let remaining = totals.remaining
        let perDay: Decimal? = {
            let days = BudgetStore.daysRemaining(in: month)
            guard isCurrent, days > 0, remaining > 0 else { return nil }
            return remaining / Decimal(days)
        }()
        return VStack(alignment: .leading, spacing: theme.spacing * 1.5) {
            Text("Budget du mois")
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)

            HStack(spacing: theme.spacing * 1.5) {
                gauge(totals: totals, state: state)
                    .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 4) {
                    if isCurrent || isPast || remaining < 0 {
                        Text(remaining >= 0 ? "Reste à dépenser" : "Dépassé de")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                        Text(budgetEuros(abs(remaining)))
                            .font(theme.largeAmountFont)
                            .foregroundStyle(remaining >= 0 ? theme.textPrimary : theme.negative)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    } else {
                        Text("Prévu ce mois")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                        Text(budgetEuros(totals.budget))
                            .font(theme.largeAmountFont)
                            .foregroundStyle(theme.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    if let perDay {
                        Text("\(budgetEuros(perDay)) / jour possible")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                    if !isPast && !isCurrent {
                        Text("Mois à venir")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gaugeAccessibility(totals: totals))

            if isCurrent {
                Label(state.message, systemImage: state.icon)
                    .font(theme.bodyFont.weight(.semibold))
                    .foregroundStyle(color(for: state))
                    .accessibilityLabel(state.message)
            }

            if isCurrent || isPast {
                counters(statuses)
            }
            if isCurrent { projection(statuses: statuses, totals: totals) }
            if isPast { review(totals) }
        }
    }

    /// Jauge circulaire avec repère « où tu devrais en être aujourd'hui ».
    private func gauge(totals: BudgetTotals, state: Pace) -> some View {
        let ratio = min(max(totals.ratio, 0), 1)
        let elapsed = BudgetStore.elapsedFraction(of: month)
        let tint = isCurrent ? color(for: state) : (totals.ratio > 1 ? theme.negative : theme.accent)
        return ZStack {
            Circle().stroke(theme.surfaceSecondary, lineWidth: 14)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isCurrent {
                // Repère : trait radial à la position du mois écoulée.
                Capsule()
                    .fill(theme.textPrimary)
                    .frame(width: 3, height: 22)
                    .offset(y: -65)
                    .rotationEffect(.degrees(elapsed * 360))
            }
            VStack(spacing: 0) {
                Text(totals.ratio, format: .percent.precision(.fractionLength(0)))
                    .font(theme.amountFont)
                    .foregroundStyle(theme.textPrimary)
                Text("dépensé")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(7)
    }

    private func gaugeAccessibility(totals: BudgetTotals) -> String {
        var text = "\(budgetEuros(totals.spent)) dépensés sur \(budgetEuros(totals.budget)), soit \(Int((totals.ratio * 100).rounded())) pour cent."
        if isCurrent {
            text += " \(Int((BudgetStore.elapsedFraction(of: month) * 100).rounded())) pour cent du mois écoulé."
        }
        return text
    }

    /// Compteurs ok / attention / dépassées.
    private func counters(_ statuses: [BudgetStatus]) -> some View {
        HStack(spacing: theme.spacing) {
            counter(statuses.filter { $0.state == .ok }.count, "dans le budget", theme.positive, "checkmark.circle.fill")
            counter(statuses.filter { $0.state == .warning }.count, "à surveiller", theme.warning, "exclamationmark.triangle.fill")
            counter(statuses.filter { $0.state == .exceeded }.count, "dépassées", theme.negative, "xmark.octagon.fill")
        }
    }

    private func counter(_ count: Int, _ label: String, _ tint: Color, _ icon: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint)
                Text("\(count)").font(theme.amountFont).foregroundStyle(theme.textPrimary)
            }
            Text(label)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.spacing * 0.6)
        .background(theme.surfaceSecondary, in: .rect(cornerRadius: theme.smallCornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) catégories \(label)")
    }

    /// Dépense estimée en fin de mois (mois en cours).
    @ViewBuilder
    private func projection(statuses: [BudgetStatus], totals: BudgetTotals) -> some View {
        let projected = statuses.reduce(Decimal(0)) {
            $0 + (store.projectedSpending(for: $1.category, month: month) ?? $1.spent)
        }
        let diff = totals.budget - projected
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fin de mois estimée")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Text(budgetEuros(projected))
                    .font(theme.amountFont)
                    .foregroundStyle(theme.textPrimary)
            }
            Spacer()
            Text(diff >= 0 ? "\(budgetEuros(diff)) sous le disponible" : "\(budgetEuros(-diff)) au-dessus du disponible")
                .font(theme.captionFont)
                .foregroundStyle(diff >= 0 ? theme.positive : theme.negative)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Bilan d'un mois passé.
    private func review(_ totals: BudgetTotals) -> some View {
        let diff = totals.remaining
        return Label(diff >= 0 ? "Économisé : \(budgetEuros(diff))" : "Dépassé de \(budgetEuros(-diff))",
                     systemImage: diff >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
            .font(theme.bodyFont.weight(.semibold))
            .foregroundStyle(diff >= 0 ? theme.positive : theme.negative)
    }
}
