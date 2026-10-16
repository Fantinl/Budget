import SwiftUI

/// Barre d'actions flottante affichée quand des opérations sont sélectionnées.
struct SelectionActionBar: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    let selected: [Transaction]
    let onCategory: (Category) -> Void
    let onAccount: (Account) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    private var editable: [Transaction] { selected.filter { !$0.isTransfer } }
    private var kinds: [TransactionKind] { TransactionKind.allCases.filter { kind in editable.contains { $0.kind == kind } } }

    /// Précision affichée sous la barre quand certaines opérations seront ignorées.
    private var hint: String? {
        var parts: [String] = []
        if selected.contains(where: \.isTransfer) { parts.append("Les virements sont ignorés") }
        if kinds.count > 1 { parts.append("Catégorie appliquée selon le type (dépense / revenu)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 4) {
            if let hint {
                Text(hint)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing) {
                    Text("\(selected.count) sélectionnée\(selected.count > 1 ? "s" : "")")
                        .font(theme.titleFont)
                        .foregroundStyle(theme.textPrimary)
                    Divider().frame(height: 20)
                    Menu {
                        ForEach(kinds) { kind in
                            Section(kind.label) {
                                ForEach(store.categories(for: kind)) { category in
                                    Button(category.label, systemImage: category.icon) { onCategory(category) }
                                }
                            }
                        }
                    } label: { Label("Catégorie", systemImage: "tag") }
                        .disabled(editable.isEmpty)
                    Menu {
                        ForEach(store.activeAccounts) { account in
                            Button(account.name) { onAccount(account) }
                        }
                    } label: { Label("Compte", systemImage: "building.columns") }
                        .disabled(editable.isEmpty)
                    Button("Dupliquer", systemImage: "plus.square.on.square", action: onDuplicate)
                        .disabled(editable.isEmpty)
                    Button("Supprimer", systemImage: "trash", role: .destructive, action: onDelete)
                        .foregroundStyle(theme.negative)
                    Button("Désélectionner", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly)
                }
                .font(theme.bodyFont)
                .menuStyle(.button)
                .buttonStyle(.plain)
                .fixedSize()
                .padding(.horizontal, theme.padding)
                .padding(.vertical, theme.spacing)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(theme.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth))
            .shadow(color: theme.cardShadowColor, radius: theme.cardShadowRadius + 4, y: theme.cardShadowY)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 640)
    }
}
