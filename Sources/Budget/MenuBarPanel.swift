#if os(macOS)
import SwiftUI
import AppKit

/// Étiquette de l'icône : symbole template, et relais d'ouverture de la fenêtre principale.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "chart.pie.fill")
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                openWindow(id: "main")
            }
    }
}

/// Panneau de la barre des menus : solde, saisie express, ajouts rapides, budgets.
struct MenuBarPanel: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage("appearance") private var appearance = AppearanceMode.system

    @State private var quickToast: QuickAddToast?

    private var monthBalance: Decimal {
        let month = store.transactions(inMonthOf: .now)
        let earned = month.filter(\.isEarning).reduce(Decimal(0)) { $0 + $1.amount }
        let spent = month.filter(\.isSpending).reduce(Decimal(0)) { $0 + $1.amount }
        return earned - spent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            header
            ExpressEntryBar(accountID: nil)
            quickAdds
            budgets
            Divider().overlay(theme.separator)
            footer
        }
        .padding(theme.padding)
        .frame(width: 320)
        .screenBackground()
        .tint(theme.accent)
        .onAppear {
            NSApp.appearance = appearance.nsAppearance
            // Place le curseur dans la saisie express une fois le panneau affiché.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .focusExpressEntry, object: nil)
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        let balance = monthBalance
        let projected = store.monthForecast().projected
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Solde du mois").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                Text(balance.euros)
                    .font(theme.largeAmountFont).monospacedDigit()
                    .foregroundStyle(balance < 0 ? theme.negative : theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: theme.spacing)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Fin de mois prévue").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                Text(projected.euros)
                    .font(theme.amountFont).monospacedDigit()
                    .foregroundStyle(projected < 0 ? theme.negative : theme.textPrimary)
            }
        }
    }

    // MARK: Ajouts rapides

    @ViewBuilder private var quickAdds: some View {
        if !store.quickExpenses.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing / 2) {
                Text("Ajout rapide").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: theme.spacing / 2)],
                          alignment: .leading, spacing: theme.spacing / 2) {
                    ForEach(store.quickExpenses.prefix(8)) { quick in chip(quick) }
                }
                if let quickToast { toastRow(quickToast) }
            }
            .animation(.smooth(duration: 0.2), value: quickToast)
        }
    }

    private func chip(_ quick: QuickExpense) -> some View {
        Button {
            let transaction = store.add(quick)
            quickToast = QuickAddToast(transaction: transaction, name: quick.name)
        } label: {
            HStack(spacing: 4) {
                CategoryBadge(category: store.category(id: quick.categoryID), size: theme.iconSize * 0.6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(quick.name).font(theme.captionFont).foregroundStyle(theme.textPrimary).lineLimit(1)
                    Text(quick.amount.euros).font(theme.captionFont).monospacedDigit()
                        .foregroundStyle(quick.kind == .income ? theme.positive : theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, theme.spacing / 2)
            .padding(.vertical, theme.spacing / 2)
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: .rect(cornerRadius: theme.smallCornerRadius))
            .contentShape(.rect(cornerRadius: theme.smallCornerRadius))
        }
        .buttonStyle(.plain)
    }

    private func toastRow(_ toast: QuickAddToast) -> some View {
        HStack(spacing: theme.spacing) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.positive)
            Text("\(toast.name) · \(toast.transaction.amount.euros) ajouté")
                .font(theme.captionFont).foregroundStyle(theme.textSecondary).lineLimit(1)
            Button("Annuler") {
                store.delete(toast.transaction)
                quickToast = nil
            }
            .font(theme.captionFont.weight(.semibold))
            .foregroundStyle(theme.accent)
            .buttonStyle(.plain)
        }
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { quickToast = nil }
        }
    }

    // MARK: Budgets

    @ViewBuilder private var budgets: some View {
        let statuses = Array(store.budgetStatuses(month: .now).prefix(3))
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Budgets").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                ForEach(statuses) { status in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(status.category.label).font(theme.captionFont)
                                .foregroundStyle(theme.textPrimary).lineLimit(1)
                            Spacer(minLength: theme.spacing)
                            Text("\(status.spent.euros) / \(status.budget.euros)")
                                .font(theme.captionFont).monospacedDigit()
                                .foregroundStyle(status.state == .exceeded ? theme.negative : theme.textSecondary)
                        }
                        ProgressView(value: min(max(status.ratio, 0), 1))
                            .progressViewStyle(.linear)
                            .tint(color(for: status.state))
                    }
                }
            }
        }
    }

    private func color(for state: BudgetState) -> Color {
        switch state {
        case .ok: theme.accent
        case .warning: theme.warning
        case .exceeded: theme.negative
        }
    }

    // MARK: Pied

    private var footer: some View {
        HStack(spacing: theme.padding) {
            Button("Ouvrir Budget") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button("Réglages…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Spacer()
            Button("Quitter") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .font(theme.captionFont)
        .foregroundStyle(theme.textSecondary)
    }
}
#endif
