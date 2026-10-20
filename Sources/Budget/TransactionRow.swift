import SwiftUI

/// Ligne d'une opération (listes des opérations et du détail d'un compte).
struct TransactionRow: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    let transaction: Transaction
    /// Affiche le nom du compte (plusieurs comptes et filtre « Tous »).
    var showAccount = false

    var body: some View {
        let category = store.category(of: transaction)
        let isTransfer = transaction.isTransfer
        HStack(spacing: theme.spacing) {
            if isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: theme.iconSize * 0.42, weight: .medium, design: theme.fontDesign))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: theme.iconSize, height: theme.iconSize)
                    .background(theme.surfaceSecondary, in: .circle)
            } else {
                CategoryBadge(category: category)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(isTransfer ? transferTitle : category.label)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                if !transaction.note.isEmpty, !(isTransfer && transaction.note == BudgetStore.defaultTransferNote) {
                    Text(transaction.note)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
                tagsLine
                if showAccount {
                    Text(store.account(id: transaction.accountID).name)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: theme.spacing)

            Text((transaction.kind == .income ? "+" : "") + transaction.signedAmount.euros)
                .font(theme.amountFont)
                .monospacedDigit()
                .foregroundStyle(isTransfer ? theme.textSecondary
                                 : transaction.kind == .income ? theme.positive : theme.textPrimary)
        }
    }

    /// Capsules des tags : trois au plus, puis « +N ».
    @ViewBuilder private var tagsLine: some View {
        let tags = store.tags(of: transaction)
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(3)) { tag in
                    TagChip(text: tag.name, color: theme.color(for: tag), selected: false)
                }
                if tags.count > 3 {
                    Text("+\(tags.count - 3)")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }

    /// « Virement vers Livret A » (sortant) ou « Virement depuis Compte courant » (entrant).
    private var transferTitle: String {
        let name = store.counterpartAccount(of: transaction)?.name
        let direction = transaction.kind == .expense ? "vers" : "depuis"
        return name.map { "Virement \(direction) \($0)" } ?? "Virement"
    }
}
