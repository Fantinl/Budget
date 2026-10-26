import SwiftUI

/// Page Budget : enveloppes par catégorie, plan du mois et équilibre de l'année.
struct BudgetPlanningView: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    @State private var month = Date.now.startOfMonth

    private var isCurrentMonth: Bool { BudgetStore.isCurrentMonth(month) }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing) {
                MonthPicker(selection: $month,
                            monthsWithData: Set(store.transactions.map { $0.date.startOfMonth }))
                BudgetSummaryCard(month: month)
                MonthPlanCard(month: month)
                BudgetEnvelopesCard(month: month)
                if isCurrentMonth { BudgetSuggestionsCard() }
                AnnualBalanceCard(year: month)
            }
            .padding(theme.padding)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Budget")
    }
}
