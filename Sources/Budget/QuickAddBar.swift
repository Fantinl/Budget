import SwiftUI

/// Message affiché par le toast après un ajout rapide.
struct QuickAddToast: Identifiable, Equatable {
    let id = UUID()
    let transaction: Transaction
    let name: String

    static func == (lhs: QuickAddToast, rhs: QuickAddToast) -> Bool { lhs.id == rhs.id }
}

/// Rangée défilante de pastilles pour ajouter les dépenses habituelles en un clic.
struct QuickAddBar: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Binding var month: Date
    @Binding var draft: Draft?
    @Binding var toast: QuickAddToast?
    /// Compte imposé aux ajouts rapides (vue d'un compte) ; nil = celui du réglage.
    var accountID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing / 2) {
            if store.quickExpenses.isEmpty {
                Text("Configure tes dépenses rapides dans les Réglages")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.leading, theme.spacing / 2)
            } else {
                Text("Ajout rapide")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.leading, theme.spacing / 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing) {
                        ForEach(Array(store.quickExpenses.enumerated()), id: \.element.id) { index, quick in
                            chip(quick, index: index)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func chip(_ quick: QuickExpense, index: Int) -> some View {
        let category = store.category(id: quick.categoryID)
        let button = Button {
            add(quick)
        } label: {
            HStack(spacing: theme.spacing / 2) {
                CategoryBadge(category: category, size: theme.iconSize * 0.7)
                Text(quick.name)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                Text(quick.amount.euros)
                    .font(theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(quick.kind == .income ? theme.positive : theme.textSecondary)
            }
            .padding(.leading, theme.spacing / 2)
            .padding(.trailing, theme.spacing)
            .padding(.vertical, theme.spacing / 2)
            .background(theme.surface, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Ajouter avec modifications…", systemImage: "square.and.pencil") {
                var transaction = store.makeTransaction(from: quick)
                if let accountID { transaction.accountID = accountID == Account.mainID ? nil : accountID }
                draft = Draft(transaction: transaction, isNew: true)
            }
        }
        return Group {
            #if os(macOS)
            if index < 9 {
                button.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            } else {
                button
            }
            #else
            button
            #endif
        }
    }

    private func add(_ quick: QuickExpense) {
        var quick = quick
        if let accountID { quick.accountID = accountID == Account.mainID ? nil : accountID }
        let transaction = store.add(quick)
        withAnimation(.smooth) {
            // Revient au mois courant pour que l'ajout soit visible.
            if month != Date.now.startOfMonth { month = Date.now.startOfMonth }
            toast = QuickAddToast(transaction: transaction, name: quick.name)
        }
    }
}

/// Bandeau discret en bas d'écran avec annulation, masqué après ~4 s.
struct QuickAddToastView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    let toast: QuickAddToast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing) {
            Text("\(toast.name) · \(toast.transaction.amount.euros) ajouté")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
            Button("Annuler") {
                store.delete(toast.transaction)
                onDismiss()
            }
            .font(theme.bodyFont.weight(.semibold))
            .foregroundStyle(theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.padding)
        .padding(.vertical, theme.spacing)
        .background(theme.surfaceSecondary, in: .capsule)
        .overlay(Capsule().strokeBorder(theme.separator))
        .shadow(radius: 8, y: 2)
        .padding(.bottom, theme.padding)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { onDismiss() }
        }
    }
}
