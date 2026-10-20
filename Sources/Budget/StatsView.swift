import SwiftUI
import Charts

struct StatsView: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store

    @State private var period: StatsPeriod = .month
    @State private var offset = 0
    @State private var showIncomeLine = true
    /// Compte analysé ; nil = tous les comptes.
    @State private var accountID: String?
    /// Catégories dépliées (opérations visibles) et celles montrées en entier.
    @State private var expandedCategories: Set<String> = []
    @State private var fullyShown: Set<String> = []
    @State private var draft: Draft?

    private static let drillDownLimit = 10

    init(accountID: String? = nil) {
        _accountID = State(initialValue: accountID)
    }

    private var transactions: [Transaction] {
        guard let accountID else { return store.transactions }
        return store.transactions.filter { $0.resolvedAccountID == accountID }
    }

    private var snapshot: StatsSnapshot {
        StatsSnapshot(transactions: transactions, period: period, offset: offset,
                      category: store.category(id:))
    }

    private var locale: Locale { Locale(identifier: "fr_FR") }

    var body: some View {
        let stats = snapshot
        ScrollView {
            VStack(spacing: theme.spacing) {
                header(stats)
                if stats.hasData {
                    keyFigures(stats)
                    if period == .month {
                        BudgetsCard(month: stats.start, detailed: true)
                        if offset == 0 && accountID == nil { ForecastCard() }
                    }
                    categoryCard(stats)
                    monthlyCard(stats)
                    topCard(stats)
                } else {
                    emptyState
                }
            }
            .padding(theme.padding)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .sheet(item: $draft) { OperationEditor(draft: $0) }
    }

    // MARK: - Période

    private func periodTitle(_ stats: StatsSnapshot) -> String {
        switch period {
        case .month:
            return stats.start.formatted(Date.FormatStyle().month(.wide).year().locale(locale)).capitalized
        case .year:
            return stats.start.formatted(Date.FormatStyle().year().locale(locale))
        case .threeMonths:
            return "3 derniers mois"
        case .all:
            return "Toutes les données"
        }
    }

    private func header(_ stats: StatsSnapshot) -> some View {
        VStack(spacing: theme.spacing) {
            Picker("Période", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: period) { _, _ in offset = 0 }

            // Filtre par compte, seulement s'il y en a plusieurs
            if store.activeAccounts.count > 1 {
                Picker("Compte", selection: $accountID) {
                    Text("Tous les comptes").tag(String?.none)
                    ForEach(store.activeAccounts) { Text($0.name).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
                .font(theme.captionFont)
            }

            if period.isNavigable {
                MonthPicker(
                    selection: dateBinding,
                    mode: period == .year ? .year : .month,
                    monthsWithData: Set(transactions.map { $0.date.startOfMonth })
                )
            } else {
                Text(periodTitle(stats))
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
            }
        }
    }

    /// Pont entre la date choisie dans le sélecteur et le décalage (`offset`) utilisé par les calculs.
    private var dateBinding: Binding<Date> {
        Binding {
            let current = Date.now.startOfMonth
            switch period {
            case .year:
                let yearStart = Calendar.current.dateInterval(of: .year, for: .now)?.start ?? current
                return yearStart.addingMonths(12 * offset)
            default:
                return current.addingMonths(offset)
            }
        } set: { newValue in
            let cal = Calendar.current
            let now = Date.now
            switch period {
            case .year:
                offset = cal.component(.year, from: newValue) - cal.component(.year, from: now)
            default:
                let months = cal.dateComponents([.month], from: now.startOfMonth, to: newValue.startOfMonth).month ?? 0
                offset = months
            }
        }
    }

    // MARK: - Chiffres clés

    private func keyFigures(_ stats: StatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Dépensé")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(stats.expenses.euros)
                        .font(theme.largeAmountFont)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    changeBadge(stats.expenseChange)
                }
                Divider().overlay(theme.separator)
                HStack(alignment: .top) {
                    figure("Revenus", stats.income.euros, color: theme.positive)
                    figure("Solde", stats.balance.euros,
                           color: stats.balance >= 0 ? theme.positive : theme.negative)
                    figure("Moy. / mois", stats.averagePerMonth.euros, color: theme.textPrimary)
                }
            }
        }
    }

    private func figure(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
            Text(value)
                .font(theme.amountFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func changeBadge(_ change: Double?) -> some View {
        if let change {
            // Une hausse des dépenses est « mauvaise »
            let up = change > 0
            let percent = abs(change).formatted(.percent.precision(.fractionLength(0)).locale(locale))
            Label("\(percent) vs période préc. à date", systemImage: up ? "arrow.up.right" : "arrow.down.right")
                .font(theme.captionFont)
                .foregroundStyle(up ? theme.negative : theme.positive)
        } else {
            Text("Pas de période préc.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Catégories

    private func categoryCard(_ stats: StatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                sectionTitle("Par catégorie")
                if stats.categories.isEmpty {
                    noExpenses
                } else {
                    Chart(stats.categories) { item in
                        SectorMark(
                            angle: .value("Montant", item.amount.doubleValue),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(theme.smallCornerRadius / 2)
                        .foregroundStyle(theme.color(for: item.category))
                    }
                    .frame(height: 180)
                    .chartLegend(.hidden)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("Total")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                            Text(stats.expenses.euros)
                                .font(theme.amountFont)
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    VStack(spacing: theme.spacing) {
                        ForEach(stats.categories) { categoryRow($0, stats: stats) }
                    }
                }
            }
        }
    }

    private func categoryRow(_ item: CategoryTotal, stats: StatsSnapshot) -> some View {
        let isOpen = expandedCategories.contains(item.id)
        return VStack(alignment: .leading, spacing: theme.spacing) {
            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    if isOpen { expandedCategories.remove(item.id) } else { expandedCategories.insert(item.id) }
                }
            } label: {
                categoryHeader(item, isOpen: isOpen)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Masquer les opérations" : "Afficher les opérations")

            if isOpen { drillDown(item, stats: stats) }
        }
    }

    private func categoryHeader(_ item: CategoryTotal, isOpen: Bool) -> some View {
        let color = theme.color(for: item.category)
        return HStack(alignment: .center, spacing: theme.spacing) {
            Image(systemName: item.category.icon)
                .font(theme.captionFont)
                .foregroundStyle(color)
                .frame(width: theme.iconSize, height: theme.iconSize)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.category.label)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(item.amount.euros)
                        .font(theme.amountFont)
                        .foregroundStyle(theme.textPrimary)
                    Text(item.share.formatted(.percent.precision(.fractionLength(0)).locale(locale)))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2)
                            .fill(theme.surfaceSecondary)
                        RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2)
                            .fill(color)
                            .frame(width: geo.size.width * item.share)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    /// Opérations de la catégorie sur la période affichée (et le compte filtré).
    private func drillDown(_ item: CategoryTotal, stats: StatsSnapshot) -> some View {
        let all = StatsSnapshot.transactions(in: item.id, from: transactions, start: stats.start, end: stats.end)
        let showAll = fullyShown.contains(item.id)
        let visible = showAll ? all : Array(all.prefix(Self.drillDownLimit))
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(visible) { t in
                Button { draft = Draft(transaction: t, isNew: false) } label: {
                    HStack(spacing: theme.spacing) {
                        Text(t.date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale)))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 56, alignment: .leading)
                        Text(t.note.isEmpty ? item.category.label : t.note)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: theme.spacing)
                        Text(t.amount.euros)
                            .font(theme.amountFont)
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if all.count > Self.drillDownLimit {
                Button(showAll ? "Réduire" : "Voir les \(all.count - Self.drillDownLimit) autres") {
                    withAnimation(.smooth(duration: 0.25)) {
                        if showAll { fullyShown.remove(item.id) } else { fullyShown.insert(item.id) }
                    }
                }
                .buttonStyle(.plain)
                .font(theme.captionFont)
                .foregroundStyle(theme.accent)
            }
        }
        .padding(.leading, theme.iconSize + theme.spacing)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Évolution mensuelle

    private func monthlyCard(_ stats: StatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                HStack {
                    sectionTitle("Évolution mensuelle")
                    Spacer()
                    Toggle("Revenus", isOn: $showIncomeLine)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .tint(theme.positive)
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #endif
                }
                // Catégories présentes dans le graphique (y compris masquées ou supprimées)
                let expenseCategories = Dictionary(stats.monthlyExpenses.map { ($0.category.id, $0.category) },
                                                   uniquingKeysWith: { a, _ in a }).values.sorted { $0.id < $1.id }
                Chart {
                    ForEach(stats.monthlyExpenses) { item in
                        BarMark(
                            x: .value("Mois", item.month, unit: .month),
                            y: .value("Dépenses", item.amount)
                        )
                        .foregroundStyle(by: .value("Catégorie", item.category.id))
                    }
                    if showIncomeLine {
                        ForEach(stats.monthlyIncome) { item in
                            LineMark(
                                x: .value("Mois", item.month, unit: .month),
                                y: .value("Revenus", item.amount),
                                series: .value("Série", "Revenus")
                            )
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(theme.positive)
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: expenseCategories.map(\.id),
                    range: expenseCategories.map { theme.color(for: $0) }
                )
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: stats.months.count > 12 ? 3 : 1)) { _ in
                        AxisValueLabel(format: Date.FormatStyle().month(.narrow).locale(locale))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(theme.separator)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(v.formatted(.number.notation(.compactName).locale(locale)))
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
    }

    // MARK: - Plus grosses dépenses

    private func topCard(_ stats: StatsSnapshot) -> some View {
        card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                sectionTitle("Plus grosses dépenses")
                if stats.topExpenses.isEmpty {
                    noExpenses
                } else {
                    ForEach(stats.topExpenses) { t in
                        let category = store.category(of: t)
                        let color = theme.color(for: category)
                        HStack(spacing: theme.spacing) {
                            Image(systemName: category.icon)
                                .font(theme.captionFont)
                                .foregroundStyle(color)
                                .frame(width: theme.iconSize, height: theme.iconSize)
                                .background(color.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.note.isEmpty ? category.label : t.note)
                                    .font(theme.bodyFont)
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)
                                Text(t.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Text(t.amount.euros)
                                .font(theme.amountFont)
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Éléments communs

    private var noExpenses: some View {
        Text("Aucune dépense sur cette période.")
            .font(theme.bodyFont)
            .foregroundStyle(theme.textSecondary)
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing) {
            Image(systemName: "chart.pie")
                .font(theme.largeAmountFont)
                .foregroundStyle(theme.textTertiary)
            Text("Aucune donnée")
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)
            Text("Ajoutez des transactions pour voir vos statistiques ici.")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.padding * 3)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(theme.titleFont)
            .foregroundStyle(theme.textPrimary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.cornerRadius))
    }
}
