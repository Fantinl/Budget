import SwiftUI

/// Élément sélectionné dans la barre latérale.
enum SidebarItem: Hashable {
    case operations, accounts, stats
}

/// Barre latérale : sections de l'app.
struct SidebarView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Binding var selection: SidebarItem
    @AppStorage(SidebarFigures.enabled) private var showFigures = true
    @AppStorage(SidebarFigures.wealth) private var showWealth = true
    @AppStorage(SidebarFigures.spent) private var showSpent = true
    @AppStorage(SidebarFigures.income) private var showIncome = false
    @AppStorage(SidebarFigures.balance) private var showBalance = true
    @AppStorage(SidebarFigures.monthCount) private var showMonthCount = true
    @AppStorage(SidebarFigures.accountCount) private var showAccountCount = false
    #if os(iOS)
    @State private var showSettings = false
    #endif

    private var monthTransactions: [Transaction] { store.transactions(inMonthOf: .now) }

    private func euros(_ value: Decimal) -> String {
        value.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
    }

    var body: some View {
        let month = monthTransactions
        let spent = month.filter(\.isSpending).reduce(Decimal(0)) { $0 + $1.amount }
        let earned = month.filter(\.isEarning).reduce(Decimal(0)) { $0 + $1.amount }

        List(selection: $selection) {
            Section {
                // Nombre d'opérations du mois en cours uniquement (« 7 en oct. »)
                SidebarRow(title: "Opérations", symbol: "list.bullet", tint: palette(2),
                           info: showFigures && showMonthCount && !month.isEmpty
                               ? "\(month.count) en \(Date.now.formatted(.dateTime.month(.abbreviated)))" : nil)
                    .tag(SidebarItem.operations)
                SidebarRow(title: "Comptes", symbol: "building.columns", tint: palette(0),
                           info: showFigures && showAccountCount ? "\(store.activeAccounts.count)" : nil)
                    .tag(SidebarItem.accounts)
                SidebarRow(title: "Statistiques", symbol: "chart.pie", tint: palette(3), info: nil)
                    .tag(SidebarItem.stats)
            } header: {
                SidebarSummary(wealth: showFigures && showWealth ? euros(store.totalBalance()) : nil,
                               spent: showFigures && showSpent ? euros(spent) : nil,
                               income: showFigures && showIncome ? euros(earned) : nil,
                               balance: showFigures && showBalance ? euros(earned - spent) : nil,
                               balanceIsNegative: earned < spent)
                    .padding(.bottom, theme.spacing)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationTitle("Budget")
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        #if os(iOS)
        .sheet(isPresented: $showSettings) { SettingsView() }
        #endif
    }

    /// Couleur de la palette des catégories, avec repli sûr.
    private func palette(_ index: Int) -> Color {
        theme.categoryPalette.indices.contains(index) ? theme.categoryPalette[index] : theme.categoryFallback
    }

    /// Pied : date du jour (et réglages sur iOS).
    private var footer: some View {
        HStack(spacing: theme.spacing) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            #if os(iOS)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
            }
            .accessibilityLabel("Réglages")
            #endif
        }
        .padding(.horizontal, theme.padding)
        .padding(.vertical, theme.spacing)
    }
}
