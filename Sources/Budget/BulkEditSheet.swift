import SwiftUI

/// Feuille « Modifier ensemble » : les champs identiques dans toute la sélection sont pré-remplis,
/// les autres affichent « Plusieurs valeurs » et ne sont modifiés que si l'utilisateur les change.
struct BulkEditSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private let ids: Set<UUID>
    private let summary: BulkSummary
    private let skippedTransfers: Int
    private let initialAmountText: String?

    @State private var amountText: String
    @State private var kind: TransactionKind?
    @State private var categoryID: String?
    @State private var accountID: String?
    @State private var noteText: String
    @State private var tagOps: [String: Bool] = [:] // true = ajouter, false = retirer
    @State private var newTagName = ""

    init(transactions: [Transaction]) {
        let editable = transactions.filter { !$0.isTransfer }
        let summary = BulkSummary(editable)
        self.summary = summary
        ids = Set(editable.map(\.id))
        skippedTransfers = transactions.count - editable.count
        initialAmountText = summary.amount.map(Self.format)
        _amountText = State(initialValue: summary.amount.map(Self.format) ?? "")
        _kind = State(initialValue: summary.kind)
        _categoryID = State(initialValue: summary.categoryID)
        _accountID = State(initialValue: summary.accountID)
        _noteText = State(initialValue: summary.note ?? "")
    }

    private static func format(_ amount: Decimal) -> String {
        "\(amount)".replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Valeurs à enregistrer

    private var amountChanged: Bool { amountText != (initialAmountText ?? "") }
    private var parsedAmount: Decimal? { AmountExpression.positiveAmount(amountText) }
    private var amountInvalid: Bool { amountChanged && parsedAmount == nil }

    private var edit: BulkEdit {
        var edit = BulkEdit()
        if amountChanged { edit.amount = parsedAmount }
        if kind != summary.kind { edit.kind = kind }
        if categoryID != summary.categoryID { edit.categoryID = categoryID }
        if accountID != summary.accountID { edit.accountID = accountID }
        if noteText != (summary.note ?? "") { edit.note = noteText }
        edit.addTagIDs = tagOps.filter { $0.value }.map(\.key)
        edit.removeTagIDs = tagOps.filter { !$0.value }.map(\.key)
        return edit
    }

    private var hasNewTag: Bool { !newTagName.trimmingCharacters(in: .whitespaces).isEmpty }
    private var canSave: Bool { !amountInvalid && (!edit.isEmpty || hasNewTag) }

    // MARK: Corps

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.padding) {
                    banner
                    Card { amountSection }
                    Card { kindAndCategory }
                    Card { accountSection }
                    Card { noteSection }
                    Card { tagsSection }
                    Card { datesSection }
                }
                .padding(theme.padding)
            }
            .background(theme.background)
            .navigationTitle("Modifier \(summary.count) opération\(summary.count > 1 ? "s" : "")")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private var banner: some View {
        if summary.isUniform {
            note("\(summary.count) opérations identiques : les modifications s’appliqueront à toutes")
        }
        if skippedTransfers > 0 {
            note("\(skippedTransfers) virement\(skippedTransfers > 1 ? "s" : "") ignoré\(skippedTransfers > 1 ? "s" : "")")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(theme.captionFont)
            .foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(theme.captionFont)
            .foregroundStyle(theme.textSecondary)
    }

    private var multiplePrompt: Text { Text("Plusieurs valeurs").foregroundStyle(theme.textTertiary) }

    // MARK: Sections

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            label("Montant")
            HStack {
                TextField("Montant", text: $amountText, prompt: summary.amount == nil ? multiplePrompt : Text("0,00").foregroundStyle(theme.textTertiary))
                    .textFieldStyle(.plain)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                Text("€").foregroundStyle(theme.textSecondary)
            }
            AmountExpressionHint(text: amountText)
        }
    }

    private var kindAndCategory: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            label("Type")
            Picker("Type", selection: $kind) {
                if summary.kind == nil { Text("Plusieurs valeurs").tag(TransactionKind?.none) }
                ForEach(TransactionKind.allCases) { Text($0.label).tag(TransactionKind?.some($0)) }
            }
            .labelsHidden()
            label("Catégorie")
            Picker("Catégorie", selection: $categoryID) {
                if summary.categoryID == nil { Text("Plusieurs valeurs").tag(String?.none) }
                ForEach(categoryKinds) { kind in
                    Section(kind.label) {
                        ForEach(categoryOptions(for: kind)) { Text($0.label).tag(String?.some($0.id)) }
                    }
                }
            }
            .labelsHidden()
        }
        .onChange(of: kind) { _, new in
            // Changement de type : la catégorie doit suivre.
            guard let new, let current = categoryID, store.category(id: current).kind != new else { return }
            categoryID = store.categories(for: new).first?.id
        }
    }

    /// Types de catégories proposés : le type choisi, sinon ceux de la sélection.
    private var categoryKinds: [TransactionKind] {
        kind.map { [$0] } ?? TransactionKind.allCases
    }

    private func categoryOptions(for kind: TransactionKind) -> [Category] {
        var options = store.categories(for: kind)
        if let id = categoryID ?? summary.categoryID, !options.contains(where: { $0.id == id }),
           store.category(id: id).kind == kind {
            options.append(store.category(id: id))
        }
        return options
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            label("Compte")
            Picker("Compte", selection: $accountID) {
                if summary.accountID == nil { Text("Plusieurs valeurs").tag(String?.none) }
                ForEach(accountOptions) { Text($0.name).tag(String?.some($0.id)) }
            }
            .labelsHidden()
        }
    }

    /// Comptes sélectionnables, plus le compte commun actuel s'il n'en fait pas partie (Izly).
    private var accountOptions: [Account] {
        var options = store.selectableAccounts
        if let id = summary.accountID, !options.contains(where: { $0.id == id }) {
            options.append(store.account(id: id))
        }
        return options
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            label("Description")
            TextField("Description", text: $noteText,
                      prompt: (summary.note == nil ? multiplePrompt : Text("Facultatif").foregroundStyle(theme.textTertiary)),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var datesSection: some View {
        HStack {
            label("Dates")
            Spacer()
            Text(dateRange)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var dateRange: String {
        guard let first = summary.firstDate, let last = summary.lastDate else { return "" }
        let style = Date.FormatStyle(locale: Locale(identifier: "fr_FR")).day().month(.abbreviated)
        if Calendar.current.isDate(first, inSameDayAs: last) { return first.formatted(style) }
        return "du \(first.formatted(.dateTime.day().locale(Locale(identifier: "fr_FR")))) au \(last.formatted(style))"
    }

    // MARK: Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            if !store.tags.isEmpty {
                label("Tags")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: theme.spacing, alignment: .leading)],
                          alignment: .leading, spacing: theme.spacing) {
                    ForEach(store.tags) { tagButton($0) }
                }
            }
            TextField("Nouveau tag", text: $newTagName, prompt: Text("Nouveau tag").foregroundStyle(theme.textTertiary))
                .textFieldStyle(.plain)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private func tagButton(_ tag: Tag) -> some View {
        let state = displayedState(of: tag)
        return Button { toggle(tag, from: state) } label: {
            HStack(spacing: 4) {
                if state != .none { Image(systemName: state == .all ? "checkmark" : "minus").font(theme.captionFont) }
                TagChip(text: tag.name, color: theme.color(for: tag), selected: state != .none)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func displayedState(of tag: Tag) -> BulkTagState {
        switch tagOps[tag.id] {
        case true: .all
        case false: .none
        default: store.tagState(tag, in: ids)
        }
    }

    private func toggle(_ tag: Tag, from state: BulkTagState) {
        let original = store.tagState(tag, in: ids)
        let target = state != .all // tout ajouter sauf si déjà partout
        // Revenir à l'état d'origine annule l'opération en attente.
        if (target && original == .all) || (!target && original == .none) {
            tagOps[tag.id] = nil
        } else {
            tagOps[tag.id] = target
        }
    }

    // MARK: Enregistrement

    private func save() {
        var edit = edit
        if hasNewTag {
            edit.addTagIDs.append(store.addTag(named: newTagName).id)
        }
        store.applyBulkEdit(ids: ids, edit)
        dismiss()
    }
}
