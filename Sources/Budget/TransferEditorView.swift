import SwiftUI

/// Création (transferID nil) ou modification d'un virement entre comptes.
struct TransferEditorView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let transferID: UUID?
    @State private var fromID: String
    @State private var toID: String
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    @FocusState private var amountFocused: Bool

    init(transferID: UUID? = nil, fromAccountID: String? = nil) {
        self.transferID = transferID
        _fromID = State(initialValue: fromAccountID ?? "")
        _toID = State(initialValue: "")
    }

    private var isNew: Bool { transferID == nil }

    /// Accepte « 12,50 », « 12.50 » ou « 1 234,5 ».
    private var parsedAmount: Decimal? {
        let cleaned = amountText.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private var legs: (out: Transaction, in: Transaction)? { transferID.flatMap { store.transferLegs(id: $0) } }

    /// Comptes actifs, plus ceux déjà utilisés par le virement édité s'ils sont archivés.
    private var availableAccounts: [Account] {
        var list = store.activeAccounts
        for id in [legs?.out.resolvedAccountID, legs?.in.resolvedAccountID].compactMap({ $0 }) where !list.contains(where: { $0.id == id }) {
            list.append(store.account(id: id))
        }
        return list
    }

    private var canSave: Bool { parsedAmount != nil && !fromID.isEmpty && !toID.isEmpty && fromID != toID }

    /// Solde d'un compte sans l'effet du virement édité.
    private func baseBalance(_ id: String) -> Decimal {
        var value = store.balance(of: store.account(id: id))
        if let legs {
            if legs.out.resolvedAccountID == id { value += legs.out.amount }
            if legs.in.resolvedAccountID == id { value -= legs.in.amount }
        }
        return value
    }

    private var warnings: [String] {
        guard let amount = parsedAmount, canSave else { return [] }
        var result: [String] = []
        let from = store.account(id: fromID)
        let to = store.account(id: toID)
        let after = baseBalance(fromID) - amount
        if after < 0 {
            result.append("Le solde de « \(from.name) » passera à \(after.euros).")
        }
        if let ceiling = to.kind.ceiling {
            let total = baseBalance(toID) + amount
            if total > ceiling {
                result.append("« \(to.name) » dépassera son plafond de \(ceiling.euros) (\(total.euros)).")
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.padding) {
                    amountField
                    accountsSection
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Card { DateField(date: $date) }
                    Card {
                        TextField("Note", text: $note, prompt: Text("Virement").foregroundStyle(theme.textTertiary), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...4)
                    }
                    if !isNew {
                        Button("Supprimer le virement", role: .destructive) { confirmDelete = true }
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.warning)
                            .buttonStyle(.plain)
                            .padding(.top, theme.spacing / 2)
                    }
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle(isNew ? "Nouveau virement" : "Modifier le virement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("Supprimer ce virement ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer le virement", role: .destructive) {
                    if let transferID { store.deleteTransfer(id: transferID) }
                    dismiss()
                }
            } message: {
                Text("Les deux opérations liées seront supprimées.")
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 640, idealHeight: 760)
        #endif
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let legs {
            fromID = legs.out.resolvedAccountID
            toID = legs.in.resolvedAccountID
            amountText = legs.out.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            date = legs.out.date
            note = legs.out.note == BudgetStore.defaultTransferNote ? "" : legs.out.note
        } else {
            let accounts = store.activeAccounts
            if fromID.isEmpty || !accounts.contains(where: { $0.id == fromID }) { fromID = store.defaultAccount.id }
            toID = accounts.first { $0.id != fromID }?.id ?? ""
            amountFocused = true
        }
    }

    private func save() {
        guard let amount = parsedAmount, canSave else { return }
        if let transferID {
            store.updateTransfer(id: transferID, from: fromID, to: toID, amount: amount, date: date, note: note)
        } else {
            store.createTransfer(from: fromID, to: toID, amount: amount, date: date, note: note)
        }
        dismiss()
    }

    // MARK: Sous-vues

    private var amountField: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            TextField("Montant", text: $amountText, prompt: Text("0,00").foregroundStyle(theme.textTertiary))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($amountFocused)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .fixedSize()
                .frame(minWidth: 80)
            Text("€").foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
        }
        .font(theme.largeAmountFont)
        .foregroundStyle(theme.textPrimary)
        .padding(.vertical, theme.spacing)
    }

    private var accountsSection: some View {
        VStack(spacing: theme.spacing) {
            Card { accountPicker(title: "De", selection: $fromID, excluded: toID) }
            Button {
                swap(&fromID, &toID)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help("Inverser les comptes")
            .accessibilityLabel("Inverser les comptes")
            Card { accountPicker(title: "Vers", selection: $toID, excluded: fromID) }
        }
    }

    /// Liste de cartes de comptes sélectionnables ; le compte de l'autre côté est grisé.
    private func accountPicker(title: String, selection: Binding<String>, excluded: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            Text(title)
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing) {
                    ForEach(availableAccounts) { account in
                        let selected = selection.wrappedValue == account.id
                        let disabled = account.id == excluded
                        Button {
                            selection.wrappedValue = account.id
                        } label: {
                            HStack(spacing: theme.spacing) {
                                AccountBadge(account: account, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(theme.bodyFont)
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                    Text(store.balance(of: account).euros)
                                        .font(theme.captionFont)
                                        .monospacedDigit()
                                        .foregroundStyle(theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(theme.spacing)
                            .background(selected ? theme.accent.opacity(0.15) : theme.surfaceSecondary,
                                        in: .rect(cornerRadius: theme.smallCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.smallCornerRadius)
                                    .stroke(selected ? theme.accent : .clear, lineWidth: 1.5)
                            )
                            .opacity(disabled ? 0.4 : 1)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(disabled)
                    }
                }
            }
        }
    }
}
