import SwiftUI

/// Confirmation de suppression ; si le compte a des opérations, on propose de l'archiver.
struct AccountDeletionDialog: ViewModifier {
    @Environment(BudgetStore.self) private var store
    @Binding var item: Account?
    var onDone: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
            titleVisibility: .visible,
            presenting: item
        ) { account in
            if store.usageCount(of: account) > 0 {
                if !account.isArchived {
                    Button("Archiver") {
                        store.archiveAccount(account)
                        onDone()
                    }
                }
            } else {
                Button("Supprimer", role: .destructive) {
                    store.deleteAccount(account)
                    onDone()
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: { account in
            let usage = store.usageCount(of: account)
            if usage > 0 {
                Text("« \(account.name) » contient \(usage) \(usage == 1 ? "opération" : "opérations") et ne peut pas être supprimé. Tu peux l'archiver : il disparaît des choix, mais ses opérations restent.")
            }
        }
    }

    private var title: String {
        guard let item else { return "" }
        return store.usageCount(of: item) > 0 ? "Suppression impossible" : "Supprimer « \(item.name) » ?"
    }
}

extension View {
    func accountDeletionDialog(item: Binding<Account?>, onDone: @escaping () -> Void = {}) -> some View {
        modifier(AccountDeletionDialog(item: item, onDone: onDone))
    }
}

/// Brouillon de compte en cours d'édition.
struct AccountDraft: Identifiable {
    let id = UUID()
    var account: Account
    var balanceText: String
    var rateText: String
    var marketValueText: String
    var marketValueDate: Date
    var bankText: String
    /// Le nom est encore celui proposé automatiquement : on le recalcule quand le type ou la banque change.
    var nameIsAuto: Bool
    let isNew: Bool

    init(newColorIndex: Int) {
        account = Account(name: "", kind: .checking, colorIndex: max(newColorIndex, 0))
        balanceText = ""
        rateText = ""
        marketValueText = ""
        marketValueDate = .now
        bankText = ""
        nameIsAuto = true
        isNew = true
        account.name = suggestedName
    }

    init(account: Account) {
        self.account = account
        balanceText = Self.format(account.initialBalance)
        rateText = account.interestRate.map(Self.format) ?? ""
        marketValueText = account.marketValue.map(Self.format) ?? ""
        marketValueDate = account.marketValueDate ?? .now
        bankText = account.bank ?? ""
        isNew = false
        nameIsAuto = false
    }

    private static func format(_ value: Decimal) -> String {
        value == 0 ? "" : value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// Accepte « 1 234,50 », « -20.5 » ; nil si illisible. Vide → nil aussi (voir `isBlank`).
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Solde initial : vide = 0 ; nil si illisible.
    var parsedBalance: Decimal? { Self.isBlank(balanceText) ? 0 : Self.parse(balanceText) }

    var trimmedBank: String { bankText.trimmingCharacters(in: .whitespaces) }

    var showsRate: Bool { account.kind.family == .savings }

    /// Nom proposé : « Livret A », « Compte courant Boursorama », « PEA Trade Republic ».
    var suggestedName: String {
        let base = account.kind.label
        return trimmedBank.isEmpty || account.kind == .cash ? base : "\(base) \(trimmedBank)"
    }

    /// Recalcule le nom s'il est encore automatique.
    mutating func refreshName() {
        if nameIsAuto || account.name.trimmingCharacters(in: .whitespaces).isEmpty {
            account.name = suggestedName
            nameIsAuto = true
        }
    }

    /// Valide les champs ; nil si l'un des montants est illisible.
    func validated() -> Account? {
        let name = account.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let balance = parsedBalance else { return nil }
        var result = account
        result.name = name
        result.initialBalance = balance
        result.bank = (trimmedBank.isEmpty || account.kind == .cash) ? nil : trimmedBank
        if showsRate && !Self.isBlank(rateText) {
            guard let rate = Self.parse(rateText) else { return nil }
            result.interestRate = rate
        } else {
            result.interestRate = nil
        }
        if account.kind.hasMarketValue && !Self.isBlank(marketValueText) {
            guard let value = Self.parse(marketValueText) else { return nil }
            result.marketValue = value
            result.marketValueDate = marketValueDate
        } else {
            result.marketValue = nil
            result.marketValueDate = nil
        }
        return result
    }
}

/// Retour à la ligne automatique pour les pastilles.
struct EditorFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

struct AccountEditorSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var draft: AccountDraft
    @State private var pendingDelete: Account?

    static let commonBanks = [
        "BNP Paribas", "Société Générale", "Crédit Agricole", "Crédit Mutuel", "LCL", "La Banque Postale",
        "Caisse d'Épargne", "Banque Populaire", "Boursorama", "Fortuneo", "Hello bank!", "Revolut", "N26",
        "Trade Republic",
    ]

    private var isMain: Bool { draft.account.id == Account.mainID }
    private var kind: AccountKind { draft.account.kind }
    private var canSave: Bool { draft.validated() != nil }

    init(draft: AccountDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.padding) {
                    preview
                    Card { typeSection }
                    if kind != .cash { Card { bankSection } }
                    Card { nameSection }
                    Card { amountsSection }
                    Card { colorSection }
                    if !draft.isNew && !isMain { dangerSection }
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .font(theme.bodyFont)
            .tint(theme.accent)
            .accountDeletionDialog(item: $pendingDelete) { dismiss() }
            .navigationTitle(draft.isNew ? "Nouveau compte" : "Modifier le compte")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        guard let account = draft.validated() else { return }
                        store.upsertAccount(account)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    // MARK: Aperçu

    private var preview: some View {
        let color = theme.color(for: draft.account)
        let name = draft.account.name.trimmingCharacters(in: .whitespaces)
        let subtitle = [draft.trimmedBank.isEmpty || kind == .cash ? nil : draft.trimmedBank, kind.label]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: theme.padding) {
            AccountBadge(account: draft.account, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Nom du compte" : name)
                    .font(theme.titleFont)
                    .foregroundStyle(name.isEmpty ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(theme.badgeFillOpacity), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous).strokeBorder(color, lineWidth: 1.5))
    }

    // MARK: Sections

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(theme.captionFont).foregroundStyle(theme.textSecondary)
    }

    private func chip(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(theme.captionFont)
            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
            .padding(.horizontal, theme.spacing)
            .padding(.vertical, 7)
            .background(selected ? theme.accent.opacity(0.15) : theme.surfaceSecondary, in: .capsule)
            .overlay(Capsule().stroke(selected ? theme.accent : .clear, lineWidth: 1.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func familyLabel(_ family: AccountFamily) -> String {
        switch family {
        case .current: "Courant"
        case .savings: "Épargne"
        case .investment: "Investissement"
        case .other: "Autre"
        }
    }

    private func familyIcon(_ family: AccountFamily) -> String {
        AccountKind.kinds(in: family).first?.icon ?? "questionmark"
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            sectionTitle("Type de compte")
            EditorFlowLayout(spacing: theme.spacing) {
                ForEach(AccountFamily.allCases) { family in
                    chip(familyLabel(family), icon: familyIcon(family), selected: kind.family == family) {
                        guard kind.family != family, let first = AccountKind.kinds(in: family).first else { return }
                        setKind(first)
                    }
                }
            }
            Divider().overlay(theme.separator)
            EditorFlowLayout(spacing: theme.spacing) {
                ForEach(AccountKind.kinds(in: kind.family)) { option in
                    chip(option.label, icon: option.icon, selected: kind == option) { setKind(option) }
                }
            }
            if let ceiling = kind.ceiling {
                Text("Plafond : \(ceiling.formatted(.currency(code: "EUR").precision(.fractionLength(0))))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func setKind(_ newKind: AccountKind) {
        draft.account.kind = newKind
        draft.refreshName()
    }

    private var bankSection: some View {
        let typed = draft.trimmedBank.lowercased()
        let known = store.banks
        let extra = Self.commonBanks.filter { name in !known.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let suggestions = (known + extra).filter {
            typed.isEmpty || ($0.lowercased().contains(typed) && $0.lowercased() != typed)
        }
        return VStack(alignment: .leading, spacing: theme.spacing) {
            sectionTitle("Banque")
            TextField("Banque", text: bankBinding, prompt: Text("Facultatif"))
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
            if !suggestions.isEmpty {
                EditorFlowLayout(spacing: theme.spacing) {
                    ForEach(suggestions, id: \.self) { bank in
                        chip(bank, selected: false) { bankBinding.wrappedValue = bank }
                    }
                }
            }
        }
    }

    private var bankBinding: Binding<String> {
        Binding(
            get: { draft.bankText },
            set: { draft.bankText = $0; draft.refreshName() }
        )
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            sectionTitle("Nom")
            TextField("Nom", text: Binding(
                get: { draft.account.name },
                set: { draft.account.name = $0; draft.nameIsAuto = false }
            ), prompt: Text("Nom du compte"))
                .textFieldStyle(.plain)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private func amountRow(_ title: String, text: Binding<String>, prompt: String, unit: String) -> some View {
        HStack {
            Text(title).foregroundStyle(theme.textPrimary)
            Spacer()
            TextField(title, text: text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(theme.textPrimary)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
            Text(unit).foregroundStyle(theme.textSecondary)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(theme.captionFont).foregroundStyle(theme.textSecondary)
    }

    private var amountsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            amountRow(kind.hasMarketValue ? "Versements initiaux" : "Solde initial",
                      text: $draft.balanceText, prompt: "0,00", unit: "€")
            hint(kind.hasMarketValue
                 ? "Total déjà versé avant les opérations saisies ici."
                 : "Le solde actuel = solde initial + revenus − dépenses du compte. Peut être négatif.")
            if draft.showsRate {
                Divider().overlay(theme.separator)
                amountRow("Taux annuel", text: $draft.rateText, prompt: "Facultatif", unit: "%")
            }
            if kind.hasMarketValue {
                Divider().overlay(theme.separator)
                amountRow("Valorisation actuelle", text: $draft.marketValueText, prompt: "Facultatif", unit: "€")
                DatePicker("Date de valorisation", selection: $draft.marketValueDate, in: ...Date.now, displayedComponents: .date)
                    .foregroundStyle(theme.textPrimary)
                hint("À mettre à jour de temps en temps depuis ton appli de banque.")
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            sectionTitle("Couleur")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
                ForEach(Array(theme.categoryPalette.enumerated()), id: \.offset) { index, color in
                    Button { draft.account.colorIndex = index } label: {
                        Circle().fill(color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if draft.account.colorIndex == index {
                                    Image(systemName: "checkmark").font(theme.captionFont.bold())
                                        .foregroundStyle(theme.onAccent)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var dangerSection: some View {
        VStack(spacing: theme.spacing) {
            Button(draft.account.isArchived ? "Désarchiver le compte" : "Archiver le compte") {
                draft.account.isArchived.toggle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            Button("Supprimer le compte", role: .destructive) {
                pendingDelete = draft.account
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.negative)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, theme.spacing / 2)
    }
}
