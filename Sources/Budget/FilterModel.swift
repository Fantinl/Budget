import SwiftUI

/// Filtres de la liste des opérations (n'affectent pas le résumé du mois).
struct OperationFilter: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case all, expense, income, transfer
        var id: Self { self }
        var label: String {
            switch self {
            case .all: "Tous"
            case .expense: "Dépenses"
            case .income: "Revenus"
            case .transfer: "Virements"
            }
        }
    }

    var kind: Kind = .all
    var categoryIDs: Set<String> = []
    var accountID: String?
    var tagIDs: Set<String> = []
    var minAmount: Decimal?
    var maxAmount: Decimal?

    var isActive: Bool { self != OperationFilter() }

    func matches(_ t: Transaction) -> Bool {
        switch kind {
        case .all: break
        case .expense: if !t.isSpending { return false }
        case .income: if !t.isEarning { return false }
        case .transfer: if !t.isTransfer { return false }
        }
        if !categoryIDs.isEmpty, !categoryIDs.contains(t.categoryID) { return false }
        if !tagIDs.isEmpty, tagIDs.isDisjoint(with: t.tagIDs ?? []) { return false }
        if let accountID, t.resolvedAccountID != accountID { return false }
        if let minAmount, t.amount < minAmount { return false }
        if let maxAmount, t.amount > maxAmount { return false }
        return true
    }
}

/// Formulaire des filtres (popover sur macOS, feuille sur iOS).
struct FilterForm: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Binding var filter: OperationFilter
    /// Masque le filtre par compte (vue d'un compte).
    var showAccount: Bool

    var body: some View {
        Form {
            Section("Type") {
                Picker("Type", selection: $filter.kind) {
                    ForEach(OperationFilter.Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if showAccount && store.selectableAccounts.count > 1 {
                Section("Compte") {
                    Picker("Compte", selection: $filter.accountID) {
                        Text("Tous").tag(String?.none)
                        ForEach(store.selectableAccounts) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    .labelsHidden()
                }
            }
            Section("Montant") {
                TextField("Minimum", value: $filter.minAmount, format: .number)
                TextField("Maximum", value: $filter.maxAmount, format: .number)
            }
            Section("Catégories") {
                ForEach(TransactionKind.allCases) { kind in
                    ForEach(store.categories(for: kind)) { category in
                        Button {
                            if filter.categoryIDs.contains(category.id) {
                                filter.categoryIDs.remove(category.id)
                            } else {
                                filter.categoryIDs.insert(category.id)
                            }
                        } label: {
                            HStack(spacing: theme.spacing) {
                                CategoryBadge(category: category, size: theme.iconSize * 0.7)
                                Text(category.label).foregroundStyle(theme.textPrimary)
                                Spacer()
                                if filter.categoryIDs.contains(category.id) {
                                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !store.tags.isEmpty {
                Section("Tags") {
                    ForEach(store.tags) { tag in
                        Button {
                            if filter.tagIDs.contains(tag.id) {
                                filter.tagIDs.remove(tag.id)
                            } else {
                                filter.tagIDs.insert(tag.id)
                            }
                        } label: {
                            HStack(spacing: theme.spacing) {
                                Circle().fill(theme.color(for: tag)).frame(width: 12, height: 12)
                                Text(tag.name).foregroundStyle(theme.textPrimary)
                                Spacer()
                                if filter.tagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if filter.isActive {
                Button("Effacer les filtres", role: .destructive) { filter = OperationFilter() }
            }
        }
        .formStyle(.grouped)
        .font(theme.bodyFont)
    }
}

/// Pastilles des filtres actifs, supprimables une à une.
struct FilterChips: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Binding var filter: OperationFilter

    var body: some View {
        if filter.isActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing) {
                    if filter.kind != .all {
                        chip(filter.kind.label) { filter.kind = .all }
                    }
                    ForEach(filter.categoryIDs.sorted(), id: \.self) { id in
                        chip(store.category(id: id).label) { filter.categoryIDs.remove(id) }
                    }
                    ForEach(store.tags.filter { filter.tagIDs.contains($0.id) }) { tag in
                        chip("#\(tag.name)") { filter.tagIDs.remove(tag.id) }
                    }
                    if let id = filter.accountID {
                        chip(store.account(id: id).name) { filter.accountID = nil }
                    }
                    if let min = filter.minAmount {
                        chip("≥ \(min.euros)") { filter.minAmount = nil }
                    }
                    if let max = filter.maxAmount {
                        chip("≤ \(max.euros)") { filter.maxAmount = nil }
                    }
                    Button("Effacer les filtres") { filter = OperationFilter() }
                        .buttonStyle(.plain)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(text)
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .font(theme.captionFont)
            .foregroundStyle(theme.accent)
            .padding(.horizontal, theme.spacing)
            .padding(.vertical, 5)
            .background(theme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .help("Retirer ce filtre")
    }
}
