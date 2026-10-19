import SwiftUI

/// Gestion des catégories (dépenses / revenus), avec masquage et réordonnancement.
struct SettingsCategoriesView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var editing: SettingsCategoryDraft?
    @State private var pendingDelete: Category?

    var body: some View {
        List {
            Text("Fixe un budget mensuel sur une catégorie de dépense pour suivre ta consommation dans le résumé du mois.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .listRowBackground(Color.clear)
            ForEach(TransactionKind.allCases) { kind in
                section(for: kind)
            }
            let hidden = store.categories.filter(\.isHidden)
            if !hidden.isEmpty {
                Section("Masquées") {
                    ForEach(hidden) { category in
                        row(category).opacity(0.5)
                    }
                }
            }
        }
        .listRowBackground(theme.surface)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .tint(theme.accent)
        .navigationTitle("Catégories")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
        #endif
        .sheet(item: $editing) { draft in
            SettingsCategorySheet(draft: draft)
        }
        .categoryDeletionDialog(item: $pendingDelete)
    }

    private func section(for kind: TransactionKind) -> some View {
        Section(kind == .expense ? "Dépenses" : "Revenus") {
            let visible = store.categories(for: kind)
            ForEach(visible) { category in
                row(category, visible: visible)
            }
            .onMove { source, destination in
                move(visible, kind: kind, from: source, to: destination)
            }
            // Ajout d'une catégorie en bas de la section
            Button {
                editing = SettingsCategoryDraft(kind: kind)
            } label: {
                Label {
                    Text(kind == .expense ? "Ajouter une catégorie de dépense" : "Ajouter une catégorie de revenu")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                } icon: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Convertit les indices de la liste visible en indices de la liste complète du store.
    private func move(_ visible: [Category], kind: TransactionKind, from source: IndexSet, to destination: Int) {
        let all = store.categories(for: kind, includeHidden: true)
        let fullSource = IndexSet(source.compactMap { i in all.firstIndex { $0.id == visible[i].id } })
        let fullDestination: Int
        if destination < visible.count {
            fullDestination = all.firstIndex { $0.id == visible[destination].id } ?? all.count
        } else if let last = visible.last, let i = all.firstIndex(where: { $0.id == last.id }) {
            fullDestination = i + 1
        } else {
            fullDestination = all.count
        }
        store.moveCategories(of: kind, from: fullSource, to: fullDestination)
    }

    /// Déplace une catégorie d'un cran (ou en tête / en fin) parmi les catégories visibles de son type.
    private func reorder(_ category: Category, in visible: [Category], _ movement: ReorderMove) {
        guard let index = visible.firstIndex(where: { $0.id == category.id }) else { return }
        move(visible, kind: category.kind, from: [index],
             to: movement.destination(from: index, count: visible.count))
    }

    private func row(_ category: Category, visible: [Category] = []) -> some View {
        let isProtected = store.isProtected(category)
        let usage = store.usageCount(of: category)
        let index = visible.firstIndex { $0.id == category.id }
        let canUp = (index ?? 0) > 0
        let canDown = index.map { $0 < visible.count - 1 } ?? false
        return HStack(spacing: theme.spacing) {
            if index != nil {
                ReorderButtons(canMoveUp: canUp, canMoveDown: canDown) { reorder(category, in: visible, $0) }
            }
            Button {
                editing = SettingsCategoryDraft(category: category)
            } label: {
                HStack(spacing: theme.spacing) {
                    CategoryBadge(category: category, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(category.label)
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textPrimary)
                            if usage > 0 {
                                Image(systemName: "lock.fill")
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textTertiary)
                            }
                        }
                        if category.kind == .expense, let budget = category.monthlyBudget, budget > 0 {
                            Text("\(budgetEuros(budget)) / mois")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                        if usage > 0 {
                            Text(usage == 1 ? "1 opération" : "\(usage) opérations")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isProtected {
                Label("Par défaut", systemImage: "pin.fill")
                    .labelStyle(.titleAndIcon)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            } else {
                CategoryTrashButton { pendingDelete = category }
            }
        }
        .swipeActions(edge: .trailing) {
            if !isProtected {
                Button(role: .destructive) { pendingDelete = category } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
            Button { toggleHidden(category) } label: {
                Label(category.isHidden ? "Réafficher" : "Masquer",
                      systemImage: category.isHidden ? "eye" : "eye.slash")
            }
            .tint(theme.textTertiary)
        }
        .contextMenu {
            if index != nil {
                ReorderMenuItems(canMoveUp: canUp, canMoveDown: canDown) { reorder(category, in: visible, $0) }
                Divider()
            }
            Button("Modifier") { editing = SettingsCategoryDraft(category: category) }
            Button(category.isHidden ? "Réafficher" : "Masquer") { toggleHidden(category) }
            if !isProtected {
                Button("Supprimer…", role: .destructive) { pendingDelete = category }
            }
        }
    }

    private func toggleHidden(_ category: Category) {
        var updated = category
        updated.isHidden.toggle()
        store.upsertCategory(updated)
    }
}

/// Bouton poubelle discret, rouge au survol.
private struct CategoryTrashButton: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundStyle(hovering ? theme.negative : theme.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Supprimer la catégorie")
        .accessibilityLabel("Supprimer la catégorie")
    }
}

/// Confirmation de suppression : simple si la catégorie est libre, explicite si elle est utilisée.
private struct CategoryDeletionDialog: ViewModifier {
    @Environment(BudgetStore.self) private var store
    @Binding var item: Category?
    var onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
            titleVisibility: .visible,
            presenting: item
        ) { category in
            let usage = store.usageCount(of: category)
            let fallback = store.fallbackCategory(for: category.kind).label
            Button(usage > 0 ? "Supprimer et déplacer dans « \(fallback) »" : "Supprimer", role: .destructive) {
                store.deleteCategory(category)
                onDeleted()
            }
            Button("Annuler", role: .cancel) {}
        } message: { category in
            let usage = store.usageCount(of: category)
            if usage > 0 {
                let fallback = store.fallbackCategory(for: category.kind).label
                Text("« \(category.label) » est utilisée par \(usage) \(usage == 1 ? "opération" : "opérations"). Si tu la supprimes, elles seront déplacées dans « \(fallback) ».")
            }
        }
    }

    private var title: String {
        guard let item else { return "" }
        return store.usageCount(of: item) > 0 ? "Catégorie utilisée" : "Supprimer « \(item.label) » ?"
    }
}

private extension View {
    func categoryDeletionDialog(item: Binding<Category?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(CategoryDeletionDialog(item: item, onDeleted: onDeleted))
    }
}

/// Brouillon de catégorie en cours d'édition (création ou modification).
struct SettingsCategoryDraft: Identifiable {
    let id = UUID()
    var category: Category
    let isNew: Bool

    init(kind: TransactionKind) {
        category = Category(label: "", icon: "cart", kind: kind, colorIndex: 0)
        isNew = true
    }

    init(category: Category) {
        self.category = category
        isNew = false
    }
}

private struct SettingsCategorySheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var draft: SettingsCategoryDraft
    @State private var pendingDelete: Category?
    @State private var budgetText = ""

    private static let icons = [
        "cart", "house", "car", "fuelpump", "tram", "airplane", "bicycle", "fork.knife",
        "cup.and.saucer", "wineglass", "gift", "tshirt", "bag", "heart", "cross.case", "pills",
        "stethoscope", "dumbbell", "gamecontroller", "film", "book", "music.note", "pawprint", "leaf",
        "bolt", "drop", "wifi", "phone", "tv", "creditcard", "banknote", "building.columns",
        "graduationcap", "figure.and.child.holdinghands", "wrench.and.screwdriver", "scissors",
        "sparkles", "repeat", "arrow.uturn.backward.circle", "plus.circle", "ellipsis.circle",
    ]

    /// Budget saisi : nil si vide ou invalide (virgule acceptée), doit être > 0.
    private var parsedBudget: Decimal? {
        let text = budgetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text), value > 0 else { return nil }
        return value
    }

    private var budgetIsValid: Bool {
        budgetText.trimmingCharacters(in: .whitespaces).isEmpty || parsedBudget != nil
    }

    private var canSave: Bool {
        !draft.category.label.trimmingCharacters(in: .whitespaces).isEmpty && budgetIsValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: theme.spacing) {
                        CategoryBadge(category: draft.category, size: 40)
                        TextField("Nom", text: $draft.category.label)
                    }
                    if draft.isNew {
                        Picker("Type", selection: $draft.category.kind) {
                            ForEach(TransactionKind.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if draft.category.kind == .expense {
                    Section {
                        TextField("Budget mensuel (facultatif)", text: $budgetText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } footer: {
                        Text(budgetIsValid ? "Laisse vide pour ne pas fixer de budget." : "Saisis un montant supérieur à 0.")
                            .foregroundStyle(budgetIsValid ? theme.textSecondary : theme.negative)
                    }
                }
                Section("Icône") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(Self.icons, id: \.self) { icon in
                            let selected = draft.category.icon == icon
                            Button { draft.category.icon = icon } label: {
                                Image(systemName: icon)
                                    .foregroundStyle(selected ? theme.accent : theme.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(selected ? theme.accent.opacity(0.15) : theme.surfaceSecondary,
                                                in: .rect(cornerRadius: theme.smallCornerRadius))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Couleur") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
                        ForEach(Array(theme.categoryPalette.enumerated()), id: \.offset) { index, color in
                            Button { draft.category.colorIndex = index } label: {
                                Circle().fill(color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if draft.category.colorIndex == index {
                                            Image(systemName: "checkmark").font(theme.captionFont.bold())
                                                .foregroundStyle(theme.surface)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !draft.isNew && !store.isProtected(draft.category) {
                    Section {
                        Button("Supprimer la catégorie", role: .destructive) {
                            pendingDelete = draft.category
                        }
                        .foregroundStyle(theme.negative)
                    }
                }
            }
            .formStyle(.grouped)
            .font(theme.bodyFont)
            .tint(theme.accent)
            .categoryDeletionDialog(item: $pendingDelete) { dismiss() }
            .onAppear {
                if let budget = draft.category.monthlyBudget {
                    budgetText = "\(budget)".replacingOccurrences(of: ".", with: ",")
                }
            }
            .navigationTitle(draft.isNew ? "Nouvelle catégorie" : "Modifier la catégorie")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        draft.category.label = draft.category.label.trimmingCharacters(in: .whitespaces)
                        draft.category.monthlyBudget = draft.category.kind == .expense ? parsedBudget : nil
                        store.upsertCategory(draft.category)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}
