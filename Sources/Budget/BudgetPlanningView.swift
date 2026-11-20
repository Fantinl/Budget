import SwiftUI

/// Page Budget : l'essentiel d'abord (reste à dépenser, enveloppes), le reste dans des sections repliables.
struct BudgetPlanningView: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    @State private var month = Date.now.startOfMonth
    @AppStorage("budget.showPlan") private var showPlan = false
    @AppStorage("budget.showYear") private var showYear = false
    @AppStorage("budget.showSuggestions") private var showSuggestions = false

    private var isCurrentMonth: Bool { BudgetStore.isCurrentMonth(month) }

    var body: some View {
        let yearTotal = store.annualBudgetBalance(year: month).total.balance
        let plan = store.monthPlan(month: month)
        let suggestionCount = isCurrentMonth ? store.budgetSuggestions().count : 0
        ScrollView {
            VStack(spacing: theme.spacing) {
                MonthPicker(selection: $month,
                            monthsWithData: Set(store.transactions.map { $0.date.startOfMonth }))
                BudgetSummaryCard(month: month)
                BudgetEnvelopesCard(month: month)
                section("Plan du mois", isOpen: $showPlan, summary: planSummary(plan)) {
                    MonthPlanCard(month: month)
                }
                section("Bilan de l’année", isOpen: $showYear, summary: yearSummary(yearTotal)) {
                    AnnualBalanceCard(year: month, embedded: true)
                }
                if suggestionCount > 0 {
                    section("Suggestions (\(suggestionCount))", isOpen: $showSuggestions, summary: nil) {
                        BudgetSuggestionsCard(embedded: true)
                    }
                }
            }
            .padding(theme.padding)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Budget")
    }

    // MARK: - Résumés d'en-tête

    private func planSummary(_ plan: MonthPlan) -> (text: String, isNegative: Bool)? {
        if plan.incomeSource == .none { return nil }
        let rest = plan.unallocated
        if rest >= 0 { return ("\(wholeEuros(rest)) libres", false) }
        return ("manque \(wholeEuros(-rest))", true)
    }

    private func yearSummary(_ total: Decimal) -> (text: String, isNegative: Bool)? {
        if total > 0 { return ("+\(wholeEuros(total)) d’avance", false) }
        if total < 0 { return ("−\(wholeEuros(-total)) de retard", true) }
        return nil
    }

    // MARK: - Section repliable

    private func section<Content: View>(_ title: String, isOpen: Binding<Bool>,
                                        summary: (text: String, isNegative: Bool)?,
                                        @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Button {
                    withAnimation(.snappy) { isOpen.wrappedValue.toggle() }
                } label: {
                    HStack(spacing: theme.spacing) {
                        Image(systemName: "chevron.right")
                            .font(theme.captionFont.bold())
                            .rotationEffect(.degrees(isOpen.wrappedValue ? 90 : 0))
                            .foregroundStyle(theme.textTertiary)
                        Text(title)
                            .font(theme.titleFont)
                            .foregroundStyle(theme.textPrimary)
                        Spacer(minLength: theme.spacing)
                        if let summary {
                            Text(summary.text)
                                .font(theme.captionFont)
                                .foregroundStyle(summary.isNegative ? theme.negative : theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isOpen.wrappedValue ? "Masquer" : "Afficher")
                if isOpen.wrappedValue { content() }
            }
        }
    }
}
