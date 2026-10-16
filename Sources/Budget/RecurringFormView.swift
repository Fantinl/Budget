import SwiftUI

/// Feuille de création / modification d'une opération récurrente.
struct RecurringFormView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let isNew: Bool
    /// Échéances déjà passées (avant aujourd'hui) d'une récurrente jamais générée : on demande quoi en faire.
    @State private var pastOccurrences: [Date] = []
    @State private var operation: RecurringOperation
    @State private var amountText: String
    @State private var hasEnd: Bool
    @State private var endDate: Date

    init(operation: RecurringOperation, isNew: Bool) {
        self.isNew = isNew
        _operation = State(initialValue: operation)
        _amountText = State(initialValue: isNew ? "" : operation.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)))
        _hasEnd = State(initialValue: operation.endDate != nil)
        _endDate = State(initialValue: operation.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: operation.startDate) ?? operation.startDate)
    }

    private var parsedAmount: Decimal? { AmountExpression.positiveAmount(amountText) }

    private var isValid: Bool {
        parsedAmount != nil && !operation.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var activeAccounts: [Account] { store.accounts.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: theme.padding) {
                    Card {
                        TextField("Nom", text: $operation.name, prompt: Text("Loyer, salaire…"))
                            .textFieldStyle(.plain)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                    }
                    VStack(spacing: 0) {
                        amountField
                        AmountExpressionHint(text: amountText)
                    }
                    Picker("Type", selection: $operation.kind) {
                        ForEach(TransactionKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Card { categoryGrid }

                    Card {
                        VStack(alignment: .leading, spacing: theme.spacing) {
                            Picker("Fréquence", selection: $operation.frequency) {
                                ForEach(RecurrenceFrequency.allCases) { Text($0.label).tag($0) }
                            }
                            if activeAccounts.count > 1 {
                                Picker("Compte", selection: Binding(
                                    get: { operation.accountID ?? "" },
                                    set: { operation.accountID = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("Compte par défaut").tag("")
                                    ForEach(activeAccounts) { Text($0.name).tag($0.id) }
                                }
                            }
                        }
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: theme.spacing / 2) {
                            Text("Première échéance").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                            DatePicker("Première échéance", selection: $operation.startDate, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .labelsHidden()
                                .environment(\.locale, Locale(identifier: "fr_FR"))
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: theme.spacing) {
                            Toggle("Date de fin", isOn: $hasEnd)
                            if hasEnd {
                                DatePicker("Fin", selection: $endDate, in: operation.startDate..., displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "fr_FR"))
                            }
                            Toggle("Active", isOn: $operation.isActive)
                        }
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    }

                    Card {
                        TextField("Description", text: $operation.note, prompt: Text("Facultatif"), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2...5)
                    }
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle(isNew ? "Nouvelle récurrente" : "Modifier")
            .confirmationDialog(
                "\(pastOccurrences.count) échéance\(pastOccurrences.count > 1 ? "s sont" : " est") déjà passée\(pastOccurrences.count > 1 ? "s" : "")",
                isPresented: Binding(get: { !pastOccurrences.isEmpty }, set: { if !$0 { pastOccurrences = [] } }),
                titleVisibility: .visible
            ) {
                Button("Créer aussi les \(pastOccurrences.count) opérations passées") { commit(skippingPast: false) }
                Button("Commencer à partir d'aujourd'hui") { commit(skippingPast: true) }
                Button("Annuler", role: .cancel) {}
            } message: {
                if let first = pastOccurrences.first {
                    Text("La première échéance (\(first.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))))) est dans le passé.")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save).disabled(!isValid)
                }
            }
            .onChange(of: operation.kind) { _, kind in
                if store.category(id: operation.categoryID).kind != kind {
                    operation.categoryID = store.categories(for: kind).first?.id ?? ""
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 600, idealHeight: 760)
        #endif
    }

    private var amountField: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            TextField("Montant", text: $amountText, prompt: Text("0,00").foregroundStyle(theme.textTertiary))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
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
        .padding(.vertical, theme.spacing)
    }

    private var availableCategories: [Category] {
        let visible = store.categories(for: operation.kind)
        let current = store.category(id: operation.categoryID)
        return visible.contains(current) || current.kind != operation.kind ? visible : visible + [current]
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: theme.spacing)], spacing: theme.spacing) {
            ForEach(availableCategories) { category in
                let selected = operation.categoryID == category.id
                Button {
                    operation.categoryID = category.id
                } label: {
                    VStack(spacing: 6) {
                        CategoryBadge(category: category)
                            .overlay(Circle().stroke(selected ? theme.accent : .clear, lineWidth: 2).padding(-3))
                        Text(category.label)
                            .font(theme.captionFont)
                            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        operation.amount = amount
        operation.name = operation.name.trimmingCharacters(in: .whitespacesAndNewlines)
        operation.note = operation.note.trimmingCharacters(in: .whitespacesAndNewlines)
        operation.endDate = hasEnd ? endDate : nil
        if activeAccounts.count <= 1 { operation.accountID = nil }
        // Jamais générée et commence dans le passé : demander s'il faut créer les échéances passées.
        if operation.lastGeneratedDate == nil,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now)) {
            let past = store.occurrences(of: operation, from: operation.startDate, to: yesterday)
            if !past.isEmpty {
                pastOccurrences = past
                return
            }
        }
        commit(skippingPast: false)
    }

    private func commit(skippingPast: Bool) {
        if skippingPast { operation.lastGeneratedDate = pastOccurrences.last }
        pastOccurrences = []
        store.upsertRecurring(operation)
        dismiss()
    }
}
