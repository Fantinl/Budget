import SwiftUI
import Charts

/// Détail d'un compte : en-tête, mois en cours, évolution du solde et opérations.
struct AccountDetailView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    let accountID: String
    @State private var editing: AccountDraft?
    @State private var draft: Draft?
    @State private var search = ""
    @State private var showTransfer = false
    @State private var showAdjust = false

    private var account: Account { store.account(id: accountID) }

    private var allTransactions: [Transaction] { store.transactions(of: account) }

    private var filtered: [Transaction] {
        guard !search.isEmpty else { return allTransactions }
        return allTransactions.filter {
            $0.note.localizedStandardContains(search) || store.category(of: $0).label.localizedStandardContains(search)
        }
    }

    /// Opérations groupées par mois, plus récent d'abord.
    private var months: [(month: Date, items: [Transaction])] {
        Dictionary(grouping: filtered) { $0.date.startOfMonth }
            .map { ($0.key, $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: theme.padding) {
                header
                if account.kind == .izly { MealPlanCard(accountID: accountID) }
                monthSummary
                chart
                searchField
                if months.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Aucune opération" : "Aucun résultat",
                                           systemImage: search.isEmpty ? "tray" : "magnifyingglass")
                        .foregroundStyle(theme.textSecondary)
                }
                ForEach(months, id: \.month) { group in
                    VStack(alignment: .leading, spacing: theme.spacing / 2) {
                        Text(group.month.formatted(.dateTime.month(.wide).year()).capitalized)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.leading, theme.spacing / 2)
                        Card(padded: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, t in
                                    if index > 0 {
                                        Divider().overlay(theme.separator)
                                            .padding(.leading, theme.padding + theme.iconSize + theme.spacing)
                                    }
                                    row(t)
                                }
                            }
                        }
                    }
                }
            }
            .padding(theme.padding)
            .padding(.bottom, 72)
        }
        .screenBackground()
        .overlay(alignment: .bottomTrailing) {
            addButton.padding([.horizontal, .bottom], theme.padding)
        }
        .navigationTitle(account.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { AccountEditorSheet(draft: $0) }
        .sheet(item: $draft) { OperationEditor(draft: $0) }
        .sheet(isPresented: $showTransfer) { TransferEditorView(fromAccountID: accountID) }
        .sheet(isPresented: $showAdjust) { AdjustBalanceSheet(accountID: accountID) }
    }

    private var header: some View {
        VStack(alignment: .trailing, spacing: theme.spacing) {
            AccountCardContent(account: account, large: true)
            if account.kind == .izly {
                Text("≈ \(store.mealsRemaining(of: account)) repas restants")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Recopie le solde affiché dans l'app Izly pour enregistrer les repas non notés.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
            HStack(spacing: theme.spacing) {
                adjustButton
                Button("Virement", systemImage: "arrow.left.arrow.right") { showTransfer = true }
                    .disabled(store.activeAccounts.count < 2 || account.isArchived)
                Button("Modifier", systemImage: "pencil") { editing = AccountDraft(account: account) }
            }
            .font(theme.captionFont)
            .tint(theme.color(for: account))
        }
        .accountCardBackground(account)
    }

    /// Mis en avant pour les comptes qu'on ne tient pas à la dépense près.
    @ViewBuilder private var adjustButton: some View {
        let button = Button("Ajuster le solde", systemImage: "equal.circle") { showAdjust = true }
            .disabled(account.isArchived)
        if [.izly, .cash, .card].contains(account.kind) {
            button.buttonStyle(.borderedProminent)
        } else {
            button
        }
    }

    private var monthSummary: some View {
        let start = Date.now.startOfMonth
        let month = allTransactions.filter { $0.date.startOfMonth == start }
        let income = month.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
        let expense = month.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount }
        let transfers = month.filter(\.isTransfer).reduce(Decimal(0)) { $0 + $1.signedAmount }
        return Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Ce mois-ci")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                HStack {
                    stat("Entrées", income.euros, theme.positive)
                    stat("Sorties", expense.euros, theme.textPrimary)
                }
                if transfers != 0 {
                    Text("dont virements : \(transfers > 0 ? "+" : "")\(transfers.euros)")
                        .font(theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(theme.captionFont).foregroundStyle(theme.textSecondary)
            Text(value).font(theme.amountFont).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Solde à la fin de chacun des 12 derniers mois (maintenant pour le mois en cours).
    private var series: [(date: Date, balance: Double)] {
        let cal = Calendar.current
        let current = Date.now.startOfMonth
        return (0..<12).reversed().compactMap { offset in
            guard let start = cal.date(byAdding: .month, value: -offset, to: current),
                  let next = cal.date(byAdding: .month, value: 1, to: start),
                  let end = cal.date(byAdding: .second, value: -1, to: next) else { return nil }
            let value = store.balance(of: account, asOf: min(end, .now))
            return (start, Double(truncating: value as NSNumber))
        }
    }

    private var chart: some View {
        let tint = theme.color(for: account)
        return Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Évolution du solde")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                Chart(series, id: \.date) { point in
                    AreaMark(x: .value("Mois", point.date, unit: .month), y: .value("Solde", point.balance))
                        .foregroundStyle(tint.opacity(0.15))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Mois", point.date, unit: .month), y: .value("Solde", point.balance))
                        .foregroundStyle(tint)
                        .interpolationMethod(.monotone)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 160)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.textTertiary)
            TextField("Rechercher dans les opérations", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button("Effacer", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .font(theme.captionFont)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.surfaceSecondary, in: .rect(cornerRadius: theme.smallCornerRadius))
    }

    private func row(_ transaction: Transaction) -> some View {
        Button {
            draft = Draft(transaction: transaction, isNew: false)
        } label: {
            TransactionRow(transaction: transaction)
                .padding(.horizontal, theme.padding)
                .padding(.vertical, theme.spacing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Modifier", systemImage: "pencil") { draft = Draft(transaction: transaction, isNew: false) }
            Button("Dupliquer", systemImage: "plus.square.on.square") { duplicate(transaction) }
            Button("Supprimer", systemImage: "trash", role: .destructive) {
                if let id = transaction.transferID { store.deleteTransfer(id: id) } else { store.delete(transaction) }
            }
        }
    }

    /// Copie à la même date, sans lien avec une récurrence ; un virement est dupliqué en entier.
    private func duplicate(_ transaction: Transaction) {
        if let id = transaction.transferID, let legs = store.transferLegs(id: id) {
            store.createTransfer(from: legs.out.resolvedAccountID, to: legs.in.resolvedAccountID,
                                 amount: legs.out.amount, date: legs.out.date, note: legs.out.note)
        } else {
            var copy = transaction
            copy.id = UUID()
            copy.recurringID = nil
            store.upsert(copy)
        }
    }

    /// Bouton flottant : nouvelle opération sur ce compte (nil = compte principal).
    private var addButton: some View {
        Button {
            var transaction = Transaction.empty(categoryID: store.categories(for: .expense).first?.id ?? "")
            if accountID != Account.mainID { transaction.accountID = accountID }
            draft = Draft(transaction: transaction, isNew: true)
        } label: {
            Label("Ajouter", systemImage: "plus")
                .font(theme.titleFont)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, theme.padding + 4)
                .padding(.vertical, theme.spacing)
                .background(theme.accent, in: .capsule)
                .shadow(color: theme.accent.opacity(0.35), radius: 10, y: 4)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
