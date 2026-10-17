import SwiftUI

/// Page « Comptes » : patrimoine, répartition, puis cartes de comptes par type ou par banque.
struct AccountsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("accountsGrouping") private var grouping = Grouping.family.rawValue
    @State private var editing: AccountDraft?
    @State private var pendingDelete: Account?
    @State private var showArchived = false
    @State private var transfer: TransferRequest?

    /// Demande d'ouverture de l'éditeur de virement (compte source facultatif).
    private struct TransferRequest: Identifiable {
        let id = UUID()
        var fromAccountID: String?
    }

    enum Grouping: String, CaseIterable {
        case family = "Type", bank = "Banque"
    }

    private var mode: Grouping { Grouping(rawValue: grouping) ?? .family }

    private struct Section: Identifiable {
        let id: String
        let title: String
        let accounts: [Account]
    }

    private var sections: [Section] {
        let active = store.activeAccounts
        switch mode {
        case .family:
            return AccountFamily.allCases.compactMap { family in
                let list = active.filter { $0.kind.family == family }
                return list.isEmpty ? nil : Section(id: family.rawValue, title: family.label, accounts: list)
            }
        case .bank:
            let groups = Dictionary(grouping: active, by: \.bankLabel)
            let noBank = Account(name: "", kind: .cash, colorIndex: 0).bankLabel
            return groups.keys
                .sorted { a, b in
                    if a == noBank { return false }
                    if b == noBank { return true }
                    return a.localizedStandardCompare(b) == .orderedAscending
                }
                .map { Section(id: $0, title: $0, accounts: groups[$0] ?? []) }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.padding) {
                    totalCard
                    Picker("Regrouper par", selection: $grouping) {
                        ForEach(Grouping.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)

                    ForEach(sections) { section in
                        sectionView(section)
                    }
                    actionsRow
                    archivedSection
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .task { await store.refreshRates() }
            .navigationTitle("Comptes")
            .navigationDestination(for: String.self) { id in
                AccountDetailView(accountID: id)
            }
            .sheet(item: $editing) { draft in
                AccountEditorSheet(draft: draft)
            }
            .sheet(item: $transfer) { TransferEditorView(fromAccountID: $0.fromAccountID) }
            .accountDeletionDialog(item: $pendingDelete)
        }
    }

    // MARK: Patrimoine

    private func familyColor(_ family: AccountFamily) -> Color {
        let index = AccountFamily.allCases.firstIndex(of: family) ?? 0
        let palette = theme.categoryPalette
        return palette.isEmpty ? theme.accent : palette[(index * 2) % palette.count]
    }

    private var totalCard: some View {
        let total = store.totalBalance()
        let families: [(AccountFamily, Decimal)] = AccountFamily.allCases.compactMap { family in
            let list = store.activeAccounts.filter { $0.kind.family == family }
            return list.isEmpty ? nil : (family, list.reduce(Decimal(0)) { $0 + store.value(of: $1) })
        }
        let positiveSum = families.reduce(0.0) { $0 + max(Double(truncating: $1.1 as NSNumber), 0) }
        return HeroCard {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Patrimoine total")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.heroTextSecondary)
                Text(total.euros)
                    .font(theme.largeAmountFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.heroTextPrimary)

                if positiveSum > 0 {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(families, id: \.0) { family, amount in
                                let share = max(Double(truncating: amount as NSNumber), 0) / positiveSum
                                if share > 0 {
                                    Capsule().fill(familyColor(family))
                                        .frame(width: max(geo.size.width * share - 2, 4))
                                }
                            }
                        }
                    }
                    .frame(height: 8)
                    .clipShape(.capsule)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(families, id: \.0) { family, amount in
                        HStack(spacing: 6) {
                            Circle().fill(familyColor(family)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(family.label)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.heroTextSecondary)
                                Text(amount.euros)
                                    .font(theme.captionFont)
                                    .monospacedDigit()
                                    .foregroundStyle(theme.heroTextPrimary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Sections et cartes

    private func sectionView(_ section: Section) -> some View {
        let subtotal = section.accounts.reduce(Decimal(0)) { $0 + store.value(of: $1) }
        return VStack(alignment: .leading, spacing: theme.spacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.title)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                if mode == .bank {
                    Text("\(section.accounts.count) \(section.accounts.count == 1 ? "compte" : "comptes")")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Text(subtotal.euros)
                    .font(theme.bodyFont)
                    .monospacedDigit()
                    .foregroundStyle(subtotal < 0 ? theme.negative : theme.textSecondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(section.accounts) { card($0) }
            }
        }
    }

    private func card(_ account: Account, archived: Bool = false) -> some View {
        NavigationLink(value: account.id) {
            AccountCardContent(account: account)
                .accountCardBackground(account, archived: archived)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Modifier…", systemImage: "pencil") { editing = AccountDraft(account: account) }
            if !account.isArchived && store.activeAccounts.count > 1 {
                Button("Virement depuis ce compte…", systemImage: "arrow.left.arrow.right") {
                    transfer = TransferRequest(fromAccountID: account.id)
                }
            }
            if account.id != Account.mainID {
                Button(account.isArchived ? "Désarchiver" : "Archiver", systemImage: "archivebox") {
                    if account.isArchived { store.unarchiveAccount(account) } else { store.archiveAccount(account) }
                }
                Button("Supprimer…", systemImage: "trash", role: .destructive) { pendingDelete = account }
            }
        }
    }

    /// Ajout de compte et virement, côte à côte.
    private var actionsRow: some View {
        let canTransfer = store.activeAccounts.count >= 2
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                addCard
                transferCard(enabled: canTransfer)
            }
            if !canTransfer {
                Text("Il faut au moins deux comptes actifs pour faire un virement.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func transferCard(enabled: Bool) -> some View {
        Button {
            transfer = TransferRequest(fromAccountID: nil)
        } label: {
            Label("Virement", systemImage: "arrow.left.arrow.right")
                .font(theme.bodyFont)
                .foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(theme.accent, in: .rect(cornerRadius: theme.cornerRadius, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(enabled ? "Virement entre deux comptes" : "Il faut au moins deux comptes actifs")
    }

    private var addCard: some View {
        Button {
            editing = AccountDraft(newColorIndex: store.accounts.count)
        } label: {
            Label("Ajouter un compte", systemImage: "plus.circle.fill")
                .font(theme.bodyFont)
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                        .strokeBorder(theme.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var archivedSection: some View {
        let archived = store.accounts.filter(\.isArchived)
        if !archived.isEmpty {
            DisclosureGroup("Archivés (\(archived.count))", isExpanded: $showArchived) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(archived) { card($0, archived: true) }
                }
                .padding(.top, theme.spacing)
            }
            .font(theme.captionFont)
            .foregroundStyle(theme.textSecondary)
        }
    }
}
