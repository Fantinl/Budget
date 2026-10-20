import SwiftUI

struct TransactionFormView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let isNew: Bool
    @State private var transaction: Transaction
    @State private var amountText: String
    @FocusState private var amountFocused: Bool
    @State private var newTagName = ""

    init(draft: Draft) {
        isNew = draft.isNew
        _transaction = State(initialValue: draft.transaction)
        _amountText = State(initialValue: draft.isNew ? "" : Self.format(draft.transaction.amount))
    }

    /// Accepte un nombre ou un calcul (« 12,5+8 »). Renvoie nil si le résultat n'est pas positif.
    private var parsedAmount: Decimal? { AmountExpression.positiveAmount(amountText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.padding) {
                    VStack(spacing: 0) {
                        amountField
                        AmountExpressionHint(text: amountText)
                    }

                    Picker("Type", selection: $transaction.kind) {
                        ForEach(TransactionKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Card { categoryGrid }

                    if store.activeAccounts.count > 1 {
                        Card { accountPicker }
                    }

                    Card {
                        DateField(date: $transaction.date)
                    }

                    Card { tagsSection }

                    Card {
                        TextField("Description", text: $transaction.note, prompt: Text("Facultatif"), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2...5)
                    }

                    if !isNew {
                        Button("Supprimer", role: .destructive) {
                            store.delete(transaction)
                            dismiss()
                        }
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.negative)
                        .buttonStyle(.plain)
                        .padding(.top, theme.spacing / 2)
                    }
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle(isNew ? "Nouvelle opération" : "Modifier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(parsedAmount == nil)
                }
            }
            .onChange(of: transaction.kind) { _, kind in
                if store.category(of: transaction).kind != kind {
                    transaction.categoryID = store.categories(for: kind).first?.id ?? ""
                }
            }
            .onAppear { amountFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 600, idealHeight: 760)
        #endif
    }

    /// Montant en grand, centré.
    private var amountField: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            TextField("Montant", text: $amountText, prompt: Text("0,00").foregroundStyle(theme.textTertiary))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($amountFocused)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .fixedSize()
                .frame(minWidth: 80)
            Text("€").foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
        }
        .font(theme.largeAmountFont)
        .foregroundStyle(theme.textPrimary)
        .padding(.vertical, theme.spacing)
    }

    /// Catégories proposées ; une catégorie masquée reste affichée si l'opération l'utilise déjà.
    private var availableCategories: [Category] {
        let visible = store.categories(for: transaction.kind)
        let current = store.category(of: transaction)
        return visible.contains(current) || current.kind != transaction.kind ? visible : visible + [current]
    }

    /// Grille de pastilles sélectionnables.
    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: theme.spacing)], spacing: theme.spacing) {
            ForEach(availableCategories) { category in
                let selected = transaction.categoryID == category.id
                Button {
                    transaction.categoryID = category.id
                } label: {
                    VStack(spacing: 6) {
                        CategoryBadge(category: category)
                            .overlay(Circle().stroke(selected ? theme.accent : .clear, lineWidth: 2).padding(-3))
                        Text(category.label)
                            .font(theme.captionFont)
                            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Comptes proposés : les actifs, plus celui de l'opération s'il est archivé.
    private var availableAccounts: [Account] {
        let current = store.account(id: transaction.accountID)
        let active = store.activeAccounts
        return active.contains(current) ? active : active + [current]
    }

    /// Rangée de pastilles de comptes (défilante si besoin).
    private var accountPicker: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            Text("Compte")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing) {
                    ForEach(availableAccounts) { account in
                        let selected = transaction.resolvedAccountID == account.id
                        Button {
                            transaction.accountID = account.id
                        } label: {
                            HStack(spacing: 6) {
                                AccountBadge(account: account, size: 24)
                                Text(account.name)
                                    .font(theme.captionFont)
                                    .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, theme.spacing)
                            .padding(.vertical, 6)
                            .background(selected ? theme.accent.opacity(0.15) : theme.surfaceSecondary, in: .capsule)
                            .overlay(Capsule().stroke(selected ? theme.accent : .clear, lineWidth: 1.5))
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Pastilles des tags (multi-sélection) et champ de création.
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            if !store.tags.isEmpty {
                Text("Tags")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: theme.spacing, alignment: .leading)],
                          alignment: .leading, spacing: theme.spacing) {
                    ForEach(store.tags) { tag in
                        Button { toggle(tag) } label: {
                            TagChip(text: tag.name, color: theme.color(for: tag), selected: isSelected(tag))
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("Nouveau tag", text: $newTagName, prompt: Text("Nouveau tag").foregroundStyle(theme.textTertiary))
                .textFieldStyle(.plain)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
                .onSubmit(addNewTag)
        }
    }

    private func isSelected(_ tag: Tag) -> Bool { (transaction.tagIDs ?? []).contains(tag.id) }

    private func toggle(_ tag: Tag) {
        var ids = transaction.tagIDs ?? []
        if let index = ids.firstIndex(of: tag.id) { ids.remove(at: index) } else { ids.append(tag.id) }
        transaction.tagIDs = ids.isEmpty ? nil : ids
    }

    private func addNewTag() {
        guard !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let tag = store.addTag(named: newTagName)
        if !isSelected(tag) { toggle(tag) }
        newTagName = ""
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        if !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addNewTag() }
        // Compte principal = nil (compatibilité avec les anciens fichiers).
        if transaction.accountID == Account.mainID { transaction.accountID = nil }
        transaction.amount = amount
        transaction.note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.upsert(transaction)
        dismiss()
    }

    private static func format(_ amount: Decimal) -> String {
        amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}
