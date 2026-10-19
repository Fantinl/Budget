import SwiftUI

/// Feuille « Ajuster le solde » : on saisit le solde réel, l'écart devient une opération.
struct AdjustBalanceSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let accountID: String
    @State private var balanceText = ""
    @State private var categoryID = ""
    @State private var note = ""
    @State private var date = Date.now
    @State private var loaded = false
    @FocusState private var balanceFocused: Bool

    private var account: Account { store.account(id: accountID) }
    private var current: Decimal { store.balance(of: account) }

    /// Accepte « 13 », « 13,50 », « 1 234,5 », « -5 » ; 0 est valide.
    private var parsedBalance: Decimal? {
        let cleaned = balanceText.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var gap: Decimal? { parsedBalance.map { store.balanceGap(of: account, to: $0) } }
    private var canSave: Bool { (gap ?? 0) != 0 }

    private var defaultNote: String {
        switch account.kind {
        case .izly: "Repas Crous non notés"
        case .cash: "Dépenses en espèces non notées"
        default: "Ajustement de solde"
        }
    }

    private var preview: (text: String, color: Color)? {
        guard let gap else { return nil }
        if gap == 0 { return ("Aucun écart : le solde est déjà juste.", theme.textSecondary) }
        let sign = gap > 0 ? "+" : "−"
        let kind = gap < 0 ? "dépense" : "revenu"
        return ("Écart : \(sign)\(abs(gap).euros) → enregistré comme \(kind)",
                gap < 0 ? theme.textPrimary : theme.positive)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.padding) {
                    Text("Solde actuel dans Budget : \(current.euros)")
                        .font(theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                    balanceField
                    if let preview {
                        Text(preview.text)
                            .font(theme.bodyFont)
                            .monospacedDigit()
                            .foregroundStyle(preview.color)
                            .multilineTextAlignment(.center)
                    }
                    if let gap, gap < 0 { categorySection }
                    Card { DateField(date: $date) }
                    Card {
                        TextField("Note", text: $note, prompt: Text(defaultNote).foregroundStyle(theme.textTertiary), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...4)
                    }
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle("Ajuster le solde de \(account.name)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 520, idealHeight: 580)
        #endif
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        note = defaultNote
        let expenses = store.categories(for: .expense)
        if account.kind == .izly, expenses.contains(where: { $0.id == "restaurants" }) {
            categoryID = "restaurants"
        } else {
            categoryID = expenses.first { $0.id == "otherExpense" }?.id ?? expenses.first?.id ?? ""
        }
        balanceFocused = true
    }

    private func save() {
        guard let value = parsedBalance, canSave else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.adjustBalance(of: account, to: value, date: date, categoryID: categoryID,
                            note: trimmed.isEmpty ? defaultNote : trimmed)
        dismiss()
    }

    // MARK: Sous-vues

    private var balanceField: some View {
        VStack(spacing: 4) {
            Text("Solde réel")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                TextField("Solde réel", text: $balanceText, prompt: Text("0,00").foregroundStyle(theme.textTertiary))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($balanceFocused)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                    .fixedSize()
                    .frame(minWidth: 80)
                Text("€").foregroundStyle(theme.textSecondary)
                Spacer(minLength: 0)
            }
            .font(theme.largeAmountFont)
            .foregroundStyle(theme.textPrimary)
        }
        .padding(.vertical, theme.spacing)
    }

    private var categorySection: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Catégorie de l'écart")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing) {
                        ForEach(store.categories(for: .expense)) { category in
                            let selected = categoryID == category.id
                            Button { categoryID = category.id } label: {
                                VStack(spacing: 4) {
                                    CategoryBadge(category: category)
                                        .overlay(Circle().stroke(selected ? theme.accent : .clear, lineWidth: 2))
                                    Text(category.label)
                                        .font(theme.captionFont)
                                        .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                                        .lineLimit(1)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(category.label)
                        }
                    }
                    .padding(2)
                }
            }
        }
    }
}
