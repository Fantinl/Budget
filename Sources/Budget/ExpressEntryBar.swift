import SwiftUI

/// Champ de saisie express (« café 2,5 hier ») placé en tête de la liste des opérations.
struct ExpressEntryBar: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme

    /// Compte de la vue courante (nil = compte par défaut).
    var accountID: String? = nil
    /// Ouvre le formulaire complet pré-rempli (⌥Entrée ou bouton) ; nil = fonction masquée.
    var onOpenForm: ((Transaction) -> Void)? = nil

    @State private var text = ""
    /// Catégorie choisie à la main, valable tant que le libellé interprété ne change pas.
    @State private var override: (label: String, id: String)?
    @State private var confirmation: Confirmation?
    @FocusState private var focused: Bool

    private struct Confirmation: Identifiable {
        let id = UUID()
        let transaction: Transaction
    }

    private var entry: ExpressEntry { ExpressEntryParser.parse(text) }

    private var categoryID: String {
        if let override, override.label == entry.label { return override.id }
        return ExpressEntryParser.guessCategoryID(label: entry.label, kind: entry.kind, categories: store.categories,
                                                  quickExpenses: store.quickExpenses, transactions: store.transactions)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing / 2) {
            field
            if let confirmation {
                confirmationRow(confirmation)
            } else if !trimmed.isEmpty {
                preview
            }
        }
        .animation(.smooth(duration: 0.2), value: trimmed.isEmpty)
        .background {
            #if os(macOS)
            // ⌘E : place le curseur dans le champ.
            Button("") { focused = true }
                .keyboardShortcut("e", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            #endif
        }
    }

    // MARK: Champ

    private var field: some View {
        HStack(spacing: theme.spacing) {
            Image(systemName: "sparkles").foregroundStyle(focused ? theme.accent : theme.textTertiary)
            TextField("Saisie express", text: $text,
                      prompt: Text("Saisie express : café 2,5 hier").foregroundStyle(theme.textTertiary))
                .textFieldStyle(.plain)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .focused($focused)
                .onSubmit(submit)
                .onChange(of: text) { confirmation = nil }
            if onOpenForm != nil, entry.amount != nil {
                Button { openForm() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textSecondary)
                    .help("Ouvrir le formulaire complet (⌥↩)")
            }
        }
        .padding(.horizontal, theme.padding)
        .padding(.vertical, theme.spacing)
        .background(theme.surfaceSecondary, in: .rect(cornerRadius: theme.smallCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.smallCornerRadius)
            .strokeBorder(focused ? theme.accent.opacity(0.6) : theme.separator))
    }

    // MARK: Aperçu

    @ViewBuilder private var preview: some View {
        let entry = entry
        if let amount = entry.amount {
            let category = store.category(id: categoryID)
            HStack(spacing: theme.spacing) {
                Menu {
                    ForEach(store.categories(for: entry.kind)) { choice in
                        Button { override = (entry.label, choice.id) } label: {
                            Label(choice.label, systemImage: choice.icon)
                        }
                    }
                } label: {
                    HStack(spacing: theme.spacing / 2) {
                        CategoryBadge(category: category, size: theme.iconSize * 0.7)
                        Text(category.label).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text(entry.label.isEmpty ? category.label : entry.label)
                    .font(theme.bodyFont).foregroundStyle(theme.textPrimary).lineLimit(1)
                Text("·").foregroundStyle(theme.textTertiary)
                Text(relativeDate(entry.date)).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                Spacer(minLength: theme.spacing)
                Text(signed(amount, entry.kind))
                    .font(theme.amountFont).monospacedDigit()
                    .foregroundStyle(entry.kind == .income ? theme.positive : theme.textPrimary)
            }
            .padding(.horizontal, theme.spacing)
        } else {
            Text("Indique un montant")
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, theme.spacing)
        }
    }

    private func confirmationRow(_ confirmation: Confirmation) -> some View {
        let transaction = confirmation.transaction
        return HStack(spacing: theme.spacing) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.positive)
            Text("\(transaction.note.isEmpty ? store.category(of: transaction).label : transaction.note) · \(signed(transaction.amount, transaction.kind)) ajouté")
                .font(theme.captionFont).foregroundStyle(theme.textSecondary).lineLimit(1)
            Button("Annuler") {
                store.delete(transaction)
                self.confirmation = nil
            }
            .font(theme.captionFont.weight(.semibold))
            .foregroundStyle(theme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, theme.spacing)
        .task(id: confirmation.id) {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self.confirmation = nil }
        }
    }

    // MARK: Actions

    private func makeTransaction() -> Transaction? {
        let entry = entry
        guard let amount = entry.amount else { return nil }
        return Transaction(amount: amount, kind: entry.kind, categoryID: categoryID, note: entry.label,
                           date: entry.date, accountID: store.accountIDForNewTransaction(accountID))
    }

    private func submit() {
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.option) { openForm(); return }
        #endif
        guard let transaction = makeTransaction() else { return }
        store.upsert(transaction)
        text = ""
        override = nil
        withAnimation(.smooth) { confirmation = Confirmation(transaction: transaction) }
        focused = true
    }

    private func openForm() {
        guard let onOpenForm, let transaction = makeTransaction() else { return }
        text = ""
        override = nil
        onOpenForm(transaction)
    }

    // MARK: Formats

    private func signed(_ amount: Decimal, _ kind: TransactionKind) -> String {
        (kind == .income ? "+" : "−") + amount.euros
    }

    private func relativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "Aujourd’hui"
        case 1: return "Hier"
        case 2: return "Avant-hier"
        default: return date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
        }
    }
}
