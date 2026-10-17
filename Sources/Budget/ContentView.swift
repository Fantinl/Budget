import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Une transaction ouverte dans le formulaire, nouvelle ou existante.
struct Draft: Identifiable {
    var transaction: Transaction
    var isNew: Bool
    var id: UUID { transaction.id }
}

struct ContentView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    #if os(macOS)
    @FocusState private var searchFocused: Bool
    #endif
    @FocusState private var listFocused: Bool
    @State private var month = Date.now.startOfMonth
    @State private var draft: Draft?
    @State private var search = ""
    @State private var toast: QuickAddToast?
    @State private var filter = OperationFilter()
    @State private var showFilters = false
    @State private var selection: Set<UUID> = []
    /// Dernière ligne cliquée (point de départ des plages ⇧-clic).
    @State private var anchor: UUID?
    /// iOS : mode sélection actif (cases à cocher).
    @State private var selectionMode = false
    @State private var confirmDelete = false
    /// Compte affiché ; nil = tous les comptes.
    var accountID: String? = nil

    private var currentAccount: Account? {
        guard let accountID else { return nil }
        return store.accounts.first { $0.id == accountID }
    }

    private var monthTransactions: [Transaction] {
        let all = store.transactions(inMonthOf: month)
        guard let accountID else { return all }
        return all.filter { $0.resolvedAccountID == accountID }
    }

    /// Débuts de mois contenant des opérations (pour les pastilles du sélecteur).
    private var monthsWithData: Set<Date> {
        Set(store.transactions.map { $0.date.startOfMonth })
    }

    private var filteredTransactions: [Transaction] {
        var result = monthTransactions
        if filter.isActive { result = result.filter(filter.matches) }
        guard !search.isEmpty else { return result }
        return result.filter {
            $0.note.localizedStandardContains(search) || store.category(of: $0).label.localizedStandardContains(search)
        }
    }

    /// Ordre d'affichage (pour les plages et « tout sélectionner »).
    private var displayedIDs: [UUID] { days.flatMap { $0.items.map(\.id) } }

    private var selectedTransactions: [Transaction] {
        filteredTransactions.filter { selection.contains($0.id) }
    }

    private var hasActiveFilterOrSearch: Bool { filter.isActive || !search.isEmpty }

    /// Transactions regroupées par jour, du plus récent au plus ancien.
    private var days: [(day: Date, items: [Transaction])] {
        Dictionary(grouping: filteredTransactions) { Calendar.current.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: theme.padding) {
                    if let currentAccount { accountHeader(currentAccount) }
                    MonthPicker(selection: $month, mode: .month, monthsWithData: monthsWithData)
                        .frame(maxWidth: .infinity)
                    FilterChips(filter: $filter)
                    ExpressEntryBar(accountID: accountID) { draft = Draft(transaction: $0, isNew: true) }
                    QuickAddBar(month: $month, draft: $draft, toast: $toast, accountID: accountID)
                    MonthSummaryView(transactions: monthTransactions, month: month)

                    if days.isEmpty {
                        ContentUnavailableView(
                            hasActiveFilterOrSearch ? "Aucun résultat" : "Aucune opération ce mois-ci",
                            systemImage: hasActiveFilterOrSearch ? "magnifyingglass" : "tray",
                            description: Text(!hasActiveFilterOrSearch ? "Ajoute une dépense avec le bouton « Ajouter »." : "")
                        )
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, theme.padding)
                    }

                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: theme.spacing / 2) {
                            Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                                .padding(.leading, theme.spacing / 2)

                            Card(padded: false) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, transaction in
                                        if index > 0 {
                                            Divider().overlay(theme.separator)
                                                .padding(.leading, theme.padding + theme.iconSize + theme.spacing)
                                        }
                                        row(transaction)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(theme.padding)
                .padding(.bottom, 72) // place pour le bouton flottant
            }
            .screenBackground()
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.escape) {
                guard !selection.isEmpty else { return .ignored }
                clearSelection()
                return .handled
            }
            .onKeyPress(.delete) { requestDelete() }
            .onKeyPress(.deleteForward) { requestDelete() }
            .onChange(of: displayedIDs) { _, ids in
                // Une ligne qui disparaît (mois, filtre, suppression) quitte la sélection.
                let valid = selection.intersection(ids)
                if valid != selection { selection = valid }
                if selection.isEmpty { selectionMode = false }
            }
            .onChange(of: selection) { _, new in
                if !new.isEmpty { listFocused = true }
            }
            .background { selectionShortcuts }
            .focusedSceneValue(\.operationActions, operationActions)
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    store.deleteTransactions(ids: selection)
                    clearSelection()
                }
            } message: {
                Text("Les virements sont supprimés avec leur opération jumelle.")
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: theme.spacing) {
                    if let toast {
                        QuickAddToastView(toast: toast) {
                            withAnimation(.smooth) { self.toast = nil }
                        }
                        .id(toast.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if selection.isEmpty {
                        HStack {
                            Spacer()
                            addButton
                        }
                        .padding([.horizontal, .bottom], theme.padding)
                    } else {
                        SelectionActionBar(
                            selected: selectedTransactions,
                            onCategory: applyCategory,
                            onAccount: applyAccount,
                            onDuplicate: duplicateSelection,
                            onDelete: { confirmDelete = true },
                            onClose: clearSelection
                        )
                        .padding([.horizontal, .bottom], theme.padding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.smooth, value: selection.isEmpty)
            #if os(iOS)
            .searchable(text: $search, prompt: "Rechercher")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    filterButton
                    Button(selectionMode ? "OK" : "Sélectionner") {
                        selectionMode.toggle()
                        if !selectionMode { clearSelection() }
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack {
                    FilterForm(filter: $filter, showAccount: accountID == nil)
                        .navigationTitle("Filtres")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("OK") { showFilters = false } }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            #else
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    filterButton
                    searchField
                }
            }
            #endif
            .sheet(item: $draft) { draft in
                OperationEditor(draft: draft)
            }
            .alert("Erreur", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    /// Nom du compte et solde actuel, en tête de la vue d'un compte.
    private func accountHeader(_ account: Account) -> some View {
        let balance = store.balance(of: account)
        return HStack(spacing: theme.spacing) {
            AccountBadge(account: account, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                Text(account.kind.label)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(balance.euros)
                    .font(theme.largeAmountFont)
                    .monospacedDigit()
                    .foregroundStyle(balance < 0 ? theme.negative : theme.textPrimary)
                Text("Solde actuel")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func row(_ transaction: Transaction) -> some View {
        let selected = selection.contains(transaction.id)
        #if os(iOS)
        let showCheck = selectionMode
        #else
        let showCheck = selected
        #endif
        return Button {
            handleTap(transaction)
        } label: {
            HStack(spacing: theme.spacing) {
                if showCheck {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? theme.accent : theme.textTertiary)
                }
                TransactionRow(transaction: transaction, showAccount: store.activeAccounts.count > 1 && accountID == nil)
            }
            .padding(.horizontal, theme.padding)
            .padding(.vertical, theme.spacing)
            .background(selected ? theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: theme.cornerRadius / 2))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Modifier", systemImage: "pencil") {
                draft = Draft(transaction: transaction, isNew: false)
            }
            if !transaction.isTransfer {
                Button("Dupliquer", systemImage: "plus.square.on.square") {
                    var copy = transaction
                    copy.id = UUID()
                    copy.date = .now
                    copy.recurringID = nil
                    draft = Draft(transaction: copy, isNew: true)
                }
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) {
                store.deleteTransactions(ids: [transaction.id])
            }
        }
    }

    // MARK: - Sélection

    private func handleTap(_ transaction: Transaction) {
        listFocused = true // ⌘A, Échap et ⌫ agissent ensuite sur la liste
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor, let from = displayedIDs.firstIndex(of: anchor),
           let to = displayedIDs.firstIndex(of: transaction.id) {
            selection = Set(displayedIDs[min(from, to)...max(from, to)])
            return
        }
        if flags.contains(.command) || flags.contains(.shift) {
            toggle(transaction.id)
            return
        }
        if !selection.isEmpty { clearSelection(); return }
        #else
        if selectionMode { toggle(transaction.id); return }
        #endif
        draft = Draft(transaction: transaction, isNew: false)
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        anchor = id
    }

    private func clearSelection() {
        selection = []
        anchor = nil
        selectionMode = false
    }

    private func requestDelete() -> KeyPress.Result {
        guard !selection.isEmpty else { return .ignored }
        confirmDelete = true
        return .handled
    }

    private var deleteTitle: String {
        let count = selection.count
        return "Supprimer \(count) opération\(count > 1 ? "s" : "") ?"
    }

    /// Boutons cachés : ⌘A (tout sélectionner), seulement quand la liste a le focus,
    /// pour laisser ⌘A aux champs de texte (recherche, saisie express…).
    private var selectionShortcuts: some View {
        Button("Tout sélectionner") { selection = Set(displayedIDs) }
            .keyboardShortcut("a", modifiers: .command)
            #if os(macOS)
            .disabled(!listFocused)
            #endif
            .hidden()
    }

    private func applyCategory(_ category: Category) {
        let ids = Set(selectedTransactions.filter { !$0.isTransfer && $0.kind == category.kind }.map(\.id))
        store.updateTransactions(ids: ids) { $0.categoryID = category.id }
    }

    private func applyAccount(_ account: Account) {
        let stored = BudgetStore.storedAccountID(account.id)
        store.updateTransactions(ids: selection) { $0.accountID = stored }
    }

    private func duplicateSelection() {
        store.duplicateTransactions(ids: selection)
        clearSelection()
    }

    /// Bouton de filtres (rempli quand un filtre est actif).
    private var filterButton: some View {
        Button {
            showFilters.toggle()
        } label: {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filtrer les opérations")
        #if os(macOS)
        .popover(isPresented: $showFilters, arrowEdge: .bottom) {
            FilterForm(filter: $filter, showAccount: accountID == nil)
                .frame(width: 340, height: 460)
        }
        #endif
    }

    #if os(macOS)
    /// Champ de recherche compact pour la barre d'outils (plus étroit que celui de `.searchable`).
    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.textTertiary)
            TextField("Rechercher", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { search = ""; searchFocused = false } // Échap
            if !search.isEmpty {
                Button("Effacer", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .font(theme.captionFont)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: 150)
        .help("Rechercher (⌘F)")
    }
    #endif

    /// Bouton flottant « Ajouter », bien visible en bas à droite.
    private var addButton: some View {
        Button {
            startNewOperation()
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
        .help("Nouvelle opération (⌘N)")
    }

    /// Nouvelle opération vide (mois et compte de la vue).
    private func startNewOperation() {
        var transaction = Transaction.empty(categoryID: store.categories(for: .expense).first?.id ?? "")
        // Si on regarde un autre mois, on pré-remplit une date dans ce mois-là.
        if month != Date.now.startOfMonth { transaction.date = month }
        // Compte de la vue s'il y en a un, sinon le compte par défaut (réglages).
        transaction.accountID = store.accountIDForNewTransaction(accountID)
        draft = Draft(transaction: transaction, isNew: true)
    }

    /// Actions proposées au menu Opérations (⌘N, ⌘E, ⌘F, ⌘←, ⌘→).
    private var operationActions: OperationActions {
        OperationActions(
            newOperation: startNewOperation,
            expressEntry: { NotificationCenter.default.post(name: .focusExpressEntry, object: nil) },
            search: searchAction,
            previousMonth: { month = month.addingMonths(-1) },
            nextMonth: month.addingMonths(1) > Date.now.startOfMonth ? nil : { month = month.addingMonths(1) }
        )
    }

    private var searchAction: (() -> Void)? {
        #if os(macOS)
        return { searchFocused = true }
        #else
        return nil
        #endif
    }
}
