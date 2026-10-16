import SwiftUI

/// Configuration des dépenses rapides (modèles de dépenses habituelles).
struct SettingsQuickExpensesView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var editing: SettingsQuickDraft?

    var body: some View {
        List {
            Section {
                ForEach(store.quickExpenses) { quick in
                    Button {
                        editing = SettingsQuickDraft(quick: quick)
                    } label: {
                        HStack(spacing: theme.spacing) {
                            CategoryBadge(category: store.category(id: quick.categoryID), size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(quick.name)
                                    .font(theme.bodyFont)
                                    .foregroundStyle(theme.textPrimary)
                                Text(store.category(id: quick.categoryID).label)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Text(quick.amount.euros)
                                .font(theme.amountFont)
                                .foregroundStyle(quick.kind == .income ? theme.positive : theme.textPrimary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { store.deleteQuickExpense(quick) } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Supprimer", role: .destructive) { store.deleteQuickExpense(quick) }
                    }
                }
                .onMove { store.moveQuickExpenses(from: $0, to: $1) }
                // Ajout en bas de la liste
                Button {
                    editing = SettingsQuickDraft()
                } label: {
                    Label {
                        Text("Ajouter une dépense rapide")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                    } icon: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } footer: {
                if store.quickExpenses.isEmpty {
                    Text("Aucun modèle. Ajoutez vos dépenses habituelles pour les saisir en un clic.")
                }
            }
        }
        .listRowBackground(theme.surface)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .tint(theme.accent)
        .navigationTitle("Dépenses rapides")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
            #endif
        }
        .sheet(item: $editing) { draft in
            SettingsQuickSheet(draft: draft)
        }
    }
}

struct SettingsQuickDraft: Identifiable {
    let id = UUID()
    var quick: QuickExpense
    var amountText: String
    let isNew: Bool

    init() {
        quick = QuickExpense(name: "", amount: 0, categoryID: "")
        amountText = ""
        isNew = true
    }

    init(quick: QuickExpense) {
        self.quick = quick
        amountText = quick.amount.formatted(.number.grouping(.never))
        isNew = false
    }
}

private struct SettingsQuickSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var draft: SettingsQuickDraft

    /// Accepte un nombre ou un calcul (« 2,5+1 »).
    private var amount: Decimal? { AmountExpression.positiveAmount(draft.amountText) }

    private var categories: [Category] { store.categories(for: draft.quick.kind) }

    private var canSave: Bool {
        !draft.quick.name.trimmingCharacters(in: .whitespaces).isEmpty
            && amount != nil
            && categories.contains { $0.id == draft.quick.categoryID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $draft.quick.name)
                    TextField("Montant", text: $draft.amountText)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                    AmountExpressionHint(text: draft.amountText)
                    Picker("Type", selection: $draft.quick.kind) {
                        ForEach(TransactionKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Catégorie", selection: $draft.quick.categoryID) {
                        ForEach(categories) { category in
                            Label(category.label, systemImage: category.icon).tag(category.id)
                        }
                    }
                    TextField("Note (facultative)", text: $draft.quick.note)
                    // Choix du compte seulement s'il y en a plusieurs (nil = compte principal).
                    if store.activeAccounts.count > 1 {
                        Picker("Compte", selection: Binding(
                            get: { draft.quick.accountID ?? "" },
                            set: { draft.quick.accountID = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Compte par défaut").tag("")
                            ForEach(store.activeAccounts) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .font(theme.bodyFont)
            .tint(theme.accent)
            .navigationTitle(draft.isNew ? "Nouveau modèle" : "Modifier le modèle")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { ensureCategory() }
            .onChange(of: draft.quick.kind) { ensureCategory() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let amount else { return }
                        draft.quick.name = draft.quick.name.trimmingCharacters(in: .whitespaces)
                        draft.quick.amount = amount
                        store.upsertQuickExpense(draft.quick)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    /// Sélectionne une catégorie valide pour le type courant.
    private func ensureCategory() {
        if !categories.contains(where: { $0.id == draft.quick.categoryID }) {
            draft.quick.categoryID = categories.first?.id ?? ""
        }
    }
}
