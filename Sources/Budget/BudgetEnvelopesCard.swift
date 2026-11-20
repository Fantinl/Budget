import SwiftUI

/// Catégorie dont on édite le budget (cible de la feuille d'édition).
private struct EnvelopeTarget: Identifiable {
    let id: String
}

/// Menu « Ajouter un budget » : catégories de dépense visibles sans budget ce mois-ci, puis l'éditeur.
struct AddBudgetMenu: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date
    @State private var editing: EnvelopeTarget?

    var body: some View {
        let budgeted = Set(store.budgetStatuses(month: month).map(\.id))   // fixes comprises
        let others = store.categories.filter { $0.kind == .expense && !$0.isHidden && !budgeted.contains($0.id) }
        Group {
            if !others.isEmpty {
                Menu {
                    ForEach(others) { category in
                        Button(category.label) { editing = EnvelopeTarget(id: category.id) }
                    }
                } label: {
                    Label("Ajouter un budget", systemImage: "plus.circle")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.accent)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .sheet(item: $editing) { EnvelopeEditorSheet(categoryID: $0.id, month: month) }
    }
}

/// Carte « Enveloppes » : charges fixes (enveloppes automatiques) puis dépenses courantes, éditeur au clic.
struct BudgetEnvelopesCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date
    @State private var editing: EnvelopeTarget?

    var body: some View {
        let statuses = store.budgetStatuses(month: month)
        let fixed = statuses.filter(\.isFixed)
        let flexible = statuses.filter { !$0.isFixed }
        let occurrences = store.fixedOccurrences(month: month)
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Enveloppes")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                if statuses.isEmpty {
                    Text("Aucun budget ce mois-ci. Fixe une enveloppe par catégorie pour suivre tes dépenses.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    if !fixed.isEmpty {
                        let spent = fixed.reduce(Decimal(0)) { $0 + $1.spent }
                        let budget = fixed.reduce(Decimal(0)) { $0 + $1.budget }
                        HStack {
                            Text("Charges fixes")
                            Spacer(minLength: theme.spacing)
                            Text("payé \(wholeEuros(spent)) sur \(wholeEuros(budget))").monospacedDigit()
                        }
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        ForEach(fixed) { row($0, occurrences: occurrences[$0.id] ?? []) }
                    }
                    if !flexible.isEmpty {
                        if !fixed.isEmpty {
                            Text("Dépenses courantes")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                        }
                        ForEach(flexible) { row($0, occurrences: []) }
                    }
                }
                AddBudgetMenu(month: month)
            }
        }
        .sheet(item: $editing) { EnvelopeEditorSheet(categoryID: $0.id, month: month) }
    }

    private func row(_ status: BudgetStatus, occurrences: [BudgetStore.FixedOccurrence]) -> some View {
        Button { editing = EnvelopeTarget(id: status.id) } label: {
            EnvelopeRow(status: status, upcomingDay: upcomingDay(occurrences))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Modifier le budget")
    }

    /// Jour de la prochaine échéance à venir (après aujourd'hui, mois en cours seulement).
    private func upcomingDay(_ occurrences: [BudgetStore.FixedOccurrence]) -> Int? {
        guard BudgetStore.isCurrentMonth(month) else { return nil }
        let cal = Calendar.current
        let now = Date.now
        guard let next = occurrences.first(where: { $0.date > now && !cal.isDate($0.date, inSameDayAs: now) }) else { return nil }
        return cal.component(.day, from: next.date)
    }
}

/// Une enveloppe : pastille, libellé, barre fine et « reste X € » ou « dépassé de X € ».
private struct EnvelopeRow: View {
    @Environment(\.theme) private var theme
    let status: BudgetStatus
    /// Jour de la prochaine échéance à venir (enveloppes fixes).
    var upcomingDay: Int?

    private var barColor: Color {
        switch status.state {
        case .ok: theme.color(for: status.category)
        case .warning: theme.warning
        case .exceeded: theme.negative
        }
    }

    private var exceeded: Bool { status.state == .exceeded }
    private var paid: Bool { status.isFixed && !exceeded && status.spent >= status.budget }

    private var trailing: String {
        if exceeded { return "dépassé de \(wholeEuros(status.overspent))" }
        if paid { return "✓ payé" }
        if status.isFixed, let upcomingDay { return "reste \(wholeEuros(status.remaining)) · le \(upcomingDay)" }
        return "reste \(wholeEuros(status.remaining))"
    }

    var body: some View {
        HStack(spacing: theme.spacing) {
            CategoryBadge(category: status.category)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.category.label)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: theme.spacing)
                    Text(trailing)
                        .font(theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(exceeded ? theme.negative : paid ? theme.positive : theme.textSecondary)
                        .lineLimit(1)
                }
                gauge
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Barre fine de consommation.
    private var gauge: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.surfaceSecondary)
                Capsule().fill(barColor)
                    .frame(width: geo.size.width * min(1, max(0, status.ratio)))
            }
        }
        .frame(height: 5)
    }
}

/// Éditeur de budget : par défaut, propre au mois, report, retrait.
struct EnvelopeEditorSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let categoryID: String
    let month: Date
    @State private var defaultText = ""
    @State private var monthText = ""
    @State private var rollover = false
    @State private var loaded = false

    private var category: Category? { store.categories.first { $0.id == categoryID } }

    private static func parse(_ text: String) -> Decimal? { AmountExpression.evaluate(text) }
    private func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    private var defaultIsValid: Bool {
        isBlank(defaultText) || (Self.parse(defaultText).map { $0 > 0 } ?? false)
    }
    /// Le budget du mois peut valoir 0 (pas de budget ce mois-là).
    private var monthIsValid: Bool {
        isBlank(monthText) || (Self.parse(monthText).map { $0 >= 0 } ?? false)
    }
    private var hasAnyBudget: Bool { !isBlank(defaultText) || !isBlank(monthText) }
    private var canSave: Bool { defaultIsValid && monthIsValid && hasAnyBudget }

    private var monthName: String {
        month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_FR")))
    }

    /// Note d'une enveloppe automatique : les récurrentes du mois qui la composent.
    private func fixedNote(_ category: Category) -> String? {
        guard store.hasFixedEnvelope(for: category, month: month),
              let items = store.fixedOccurrences(month: month)[category.id], !items.isEmpty else { return nil }
        let cal = Calendar.current
        let list = items.map { "\($0.name) \(wholeEuros($0.amount)) le \(cal.component(.day, from: $0.date))" }
            .joined(separator: ", ")
        return "Enveloppe automatique : somme de tes dépenses récurrentes de ce mois (\(list)). Fixe un budget pour la remplacer."
    }

    private func text(for value: Decimal) -> String {
        "\(value)".replacingOccurrences(of: ".", with: ",")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let category {
                    Section {
                        HStack(spacing: theme.spacing) {
                            CategoryBadge(category: category, size: 40)
                            Text(category.label).font(theme.titleFont)
                        }
                    }
                    if let note = fixedNote(category) {
                        Section { Text(note).font(theme.captionFont).foregroundStyle(theme.textSecondary) }
                    }
                    Section {
                        TextField("Budget par défaut (€ / mois)", text: $defaultText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    } header: {
                        Text("Tous les mois")
                    } footer: {
                        Text(defaultIsValid ? "Montant appliqué à chaque mois, sauf budget propre à un mois."
                                            : "Saisis un montant supérieur à 0.")
                            .foregroundStyle(defaultIsValid ? theme.textSecondary : theme.negative)
                    }
                    Section {
                        TextField("Budget pour ce mois (facultatif)", text: $monthText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        if !isBlank(monthText) {
                            Button("Revenir au budget par défaut") { monthText = "" }
                                .foregroundStyle(theme.accent)
                        }
                    } header: {
                        Text("Pour \(monthName) seulement")
                    } footer: {
                        Text(monthIsValid ? "Saisis 0 pour ne pas avoir de budget ce mois-là."
                                          : "Saisis un montant positif ou nul.")
                            .foregroundStyle(monthIsValid ? theme.textSecondary : theme.negative)
                    }
                    Section {
                        Toggle("Reporter le reste sur le mois suivant", isOn: $rollover)
                    } footer: {
                        Text("Ce que tu n'as pas dépensé (ou ton dépassement) s'ajoute au budget du mois suivant. Remis à zéro en janvier.")
                    }
                    if store.plannedBudget(for: category, month: month) > 0 || category.monthlyBudget != nil {
                        Section {
                            Button("Retirer le budget", role: .destructive) {
                                store.removeBudget(for: category)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Budget")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func load() {
        guard !loaded, let category else { return }
        loaded = true
        if let budget = category.monthlyBudget, budget > 0 { defaultText = text(for: budget) }
        if let override = category.budgetOverrides?[BudgetStore.monthKey(month)] { monthText = text(for: override) }
        rollover = category.budgetRollover == true
    }

    private func save() {
        guard let category, canSave else { return }
        store.setMonthlyBudget(isBlank(defaultText) ? nil : Self.parse(defaultText), for: category)
        store.setBudgetOverride(isBlank(monthText) ? nil : Self.parse(monthText), for: category, month: month)
        if (category.budgetRollover == true) != rollover { store.setBudgetRollover(rollover, for: category) }
        dismiss()
    }
}

/// Carte « Suggestions » : budgets proposés d'après les derniers mois.
struct BudgetSuggestionsCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    /// Contenu d'une section repliable : ni carte ni titre.
    var embedded = false

    var body: some View {
        let suggestions = store.budgetSuggestions()
        if !suggestions.isEmpty {
            let content = VStack(alignment: .leading, spacing: theme.spacing) {
                HStack {
                    if !embedded {
                        Text("Suggestions")
                            .font(theme.titleFont)
                            .foregroundStyle(theme.textPrimary)
                    }
                    Spacer()
                    if suggestions.count > 1 {
                        Button("Tout appliquer") { suggestions.forEach(store.apply) }
                            .buttonStyle(.plain)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.accent)
                    }
                }
                ForEach(suggestions) { suggestion in
                    row(suggestion)
                }
            }
            if embedded { content } else { Card { content } }
        }
    }

    private func row(_ suggestion: BudgetSuggestion) -> some View {
        HStack(alignment: .top, spacing: theme.spacing) {
            CategoryBadge(category: suggestion.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.category.label)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(suggestion.reason.label)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Text("Moyenne sur \(suggestion.monthsAnalysed) mois : \(budgetEuros(suggestion.average))")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textSecondary)
                Text(suggestion.current.map { "\(budgetEuros($0)) → \(budgetEuros(suggestion.suggested))" }
                     ?? "Budget suggéré : \(budgetEuros(suggestion.suggested))")
                    .font(theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            Spacer(minLength: theme.spacing)
            Button("Appliquer") { store.apply(suggestion) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(theme.accent)
                .accessibilityLabel("Appliquer la suggestion pour \(suggestion.category.label)")
        }
    }
}
