import SwiftUI
import Charts

/// Équilibre à l'année : un dépassement d'un mois a-t-il été rattrapé les mois suivants ?
struct AnnualBalanceCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let year: Date

    // Dimensions du tableau
    private let nameWidth: CGFloat = 150
    private let cellWidth: CGFloat = 46
    private let cellHeight: CGFloat = 30
    private let balanceWidth: CGFloat = 70
    private let trendWidth: CGFloat = 96

    var body: some View {
        let balance = store.annualBudgetBalance(year: year)
        let yearNumber = Calendar.current.component(.year, from: balance.year)
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Équilibre \(String(yearNumber))")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                if balance.rows.isEmpty {
                    emptyState
                } else {
                    summary(balance.total)
                    if !balance.total.counted.isEmpty { chart(balance) }
                    heatmap(balance)
                    legend
                }
            }
        }
    }

    // MARK: - État vide

    private var emptyState: some View {
        Text("Aucune catégorie n'a de budget cette année. Définis des budgets pour suivre ton équilibre.")
            .font(theme.bodyFont)
            .foregroundStyle(theme.textSecondary)
    }

    // MARK: - Synthèse

    private func summary(_ total: AnnualBudgetRow) -> some View {
        let value = total.balance
        let sentence: String
        let color: Color
        if value < 0 {
            sentence = "\(budgetEuros(-value)) à rattraper"
            color = theme.negative
        } else if value == 0 {
            sentence = "À l'équilibre sur l'année"
            color = theme.textPrimary
        } else {
            sentence = "+\(budgetEuros(value)) d'avance sur l'année"
            color = theme.positive
        }
        let count = total.counted.count
        let exceeded = total.exceededMonths
        let detail = "\(count) mois comptés · \(exceeded) mois dépassé\(exceeded > 1 ? "s" : "")"
        return VStack(alignment: .leading, spacing: 2) {
            Text(sentence).font(theme.amountFont).foregroundStyle(color)
            Text(detail).font(theme.captionFont).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Graphique

    private func chart(_ balance: AnnualBudgetBalance) -> some View {
        let counted = balance.total.counted
        let running = balance.total.runningBalance
        let current = counted.first(where: \.isCurrent)?.month
        let end = balance.year.addingMonths(12)
        return Chart {
            RuleMark(y: .value("Zéro", 0))
                .foregroundStyle(theme.textTertiary)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if let current {
                RuleMark(x: .value("Mois", current, unit: .month))
                    .foregroundStyle(theme.accent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("en cours").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                    }
            }
            ForEach(counted) { cell in
                BarMark(x: .value("Mois", cell.month, unit: .month),
                        y: .value("Écart", cell.difference.doubleValue))
                    .foregroundStyle(cell.difference >= 0 ? theme.positive : theme.negative)
                    .cornerRadius(theme.smallCornerRadius / 2)
            }
            ForEach(Array(running.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Mois", point.month, unit: .month),
                         y: .value("Cumul", point.balance.doubleValue),
                         series: .value("Série", "cumul"))
                    .foregroundStyle(theme.accent)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Mois", point.month, unit: .month),
                          y: .value("Cumul", point.balance.doubleValue))
                    .foregroundStyle(theme.accent)
                    .symbolSize(30)
            }
        }
        .chartXScale(domain: balance.year...end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        Text(Self.shortMonth(date))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(theme.separator)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Self.compact(Decimal(amount), signed: false))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Graphique de l'écart mensuel et du cumul de l'année")
    }

    // MARK: - Carte de chaleur

    private func heatmap(_ balance: AnnualBudgetBalance) -> some View {
        let months = balance.total.cells
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                // En-têtes
                HStack(spacing: 3) {
                    Color.clear.frame(width: nameWidth, height: 1)
                    ForEach(months) { cell in
                        Text(Self.shortMonth(cell.month))
                            .font(theme.captionFont)
                            .foregroundStyle(cell.isCurrent ? theme.accent : theme.textSecondary)
                            .frame(width: cellWidth)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text("Cumul").frame(width: balanceWidth, alignment: .trailing)
                    Text("Tendance").frame(width: trendWidth)
                }
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)

                ForEach(balance.rows) { row in
                    heatmapRow(row)
                    if let catchUp = row.catchUpPerMonth, row.trend == .behind {
                        Text("≤ \(budgetEuros(catchUp))/mois jusqu'en décembre pour rattraper")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.leading, nameWidth + 3)
                    }
                }
                Rectangle().fill(theme.separator).frame(height: 1)
                    .padding(.vertical, 2)
                heatmapRow(balance.total)
            }
            .padding(.vertical, 2)
        }
    }

    private func heatmapRow(_ row: AnnualBudgetRow) -> some View {
        let name = row.category?.label ?? "Total"
        return HStack(spacing: 3) {
            HStack(spacing: 8) {
                if let category = row.category {
                    CategoryBadge(category: category, size: 24)
                }
                Text(name)
                    .font(row.category == nil ? theme.titleFont : theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: nameWidth, alignment: .leading)

            ForEach(row.cells) { cell in
                heatCell(cell, name: name)
            }

            Text(Self.compact(row.balance, signed: true))
                .font(theme.amountFont)
                .foregroundStyle(row.balance < 0 ? theme.negative : (row.balance > 0 ? theme.positive : theme.textSecondary))
                .frame(width: balanceWidth, alignment: .trailing)
                .help("Cumul de l'année : \(Self.signedEuros(row.balance))")
                .accessibilityLabel("\(name), cumul de l'année \(Self.signedEuros(row.balance))")

            trendBadge(row.trend)
                .frame(width: trendWidth)
        }
    }

    private func heatCell(_ cell: AnnualBudgetCell, name: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2, style: .continuous)
        let month = Self.longMonth(cell.month)
        let counted = cell.isCounted
        let tint: Color = cell.difference >= 0 ? theme.positive : theme.negative
        let ratio: Double = {
            guard cell.planned > 0 else { return cell.spent > 0 ? 1 : 0 }
            return min(1, abs((cell.difference / cell.planned).doubleValue))
        }()
        let help = "\(month) · Budget \(budgetEuros(cell.planned)) · Dépensé \(budgetEuros(cell.spent))"
        let label: String = counted
            ? "\(name), \(month), \(Self.signedEuros(cell.difference)), budget \(budgetEuros(cell.planned)), dépensé \(budgetEuros(cell.spent))"
            : "\(name), \(month), \(cell.isFuture ? "à venir, " : "")budget \(budgetEuros(cell.planned))"
        return ZStack {
            shape.fill(counted ? tint.opacity(0.12 + 0.5 * ratio) : theme.surfaceSecondary)
            if counted {
                Text(Self.compact(cell.difference, signed: true))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textPrimary)
            } else if cell.planned > 0 {
                Text(Self.compact(cell.planned, signed: false))
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .overlay {
            if cell.isCurrent { shape.strokeBorder(theme.accent, lineWidth: 1.5) }
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + (cell.isCurrent ? ", mois en cours" : ""))
    }

    private func trendBadge(_ trend: AnnualBudgetTrend) -> some View {
        let color: Color = switch trend {
        case .onTrack: theme.positive
        case .recovered: theme.warning
        case .behind: theme.negative
        }
        return Text(trend.label)
            .font(theme.captionFont)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule)
    }

    // MARK: - Légende

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(theme.positive.opacity(0.45), "Économie")
            legendItem(theme.negative.opacity(0.45), "Dépassement")
            legendItem(theme.surfaceSecondary, "Non compté / à venir (budget prévu)")
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(theme.accent, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                Text("En cours")
            }
        }
        .font(theme.captionFont)
        .foregroundStyle(theme.textSecondary)
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }

    // MARK: - Formats

    private static func monthFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.setLocalizedDateFormatFromTemplate(format)
        return f
    }

    /// « janv. », « févr. »…
    private static func shortMonth(_ date: Date) -> String { monthFormatter("MMM").string(from: date) }
    private static func longMonth(_ date: Date) -> String { monthFormatter("MMMM").string(from: date) }

    /// Montant compact : « +12 », « −45 », « 1,2k ».
    private static func compact(_ value: Decimal, signed: Bool) -> String {
        let number = value.doubleValue
        let magnitude = abs(number)
        let body: String
        if magnitude >= 1000 {
            body = (magnitude / 1000).formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0...1))) + "k"
        } else {
            body = magnitude.formatted(.number.locale(Locale(identifier: "fr_FR")).precision(.fractionLength(0)))
        }
        if number < 0, body != "0" { return "−" + body }
        return (signed && number > 0 && body != "0" ? "+" : "") + body
    }

    private static func signedEuros(_ value: Decimal) -> String {
        value < 0 ? "−" + budgetEuros(-value) : (value > 0 ? "+" + budgetEuros(value) : budgetEuros(value))
    }
}
