import SwiftUI

/// Catégorie dont on édite le budget (cible de la feuille d'édition).
private struct EnvelopeTarget: Identifiable {
    let id: String
}

/// Carte « Enveloppes » : budgets par catégorie du mois, avec rythme, projection et report.
struct BudgetEnvelopesCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date
    @State private var editing: EnvelopeTarget?

    private var isCurrent: Bool { BudgetStore.isCurrentMonth(month) }

    /// Catégories de dépense visibles qui n'ont pas de budget ce mois-ci.
    private func unbudgeted(_ statuses: [BudgetStatus]) -> [Category] {
        let budgeted = Set(statuses.map(\.id))
        return store.categories.filter { $0.kind == .expense && !$0.isHidden && !budgeted.contains($0.id) }
    }

    var body: some View {
        let statuses = store.budgetStatuses(month: month)
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
                    ForEach(statuses) { status in
                        Button { editing = EnvelopeTarget(id: status.id) } label: {
                            EnvelopeRow(status: status, month: month, isCurrent: isCurrent)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Modifier le budget")
                    }
                }
                let others = unbudgeted(statuses)
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
                if !statuses.isEmpty {
                    Divider().overlay(theme.separator)
                    let spent = statuses.reduce(Decimal(0)) { $0 + $1.spent }
                    let available = statuses.reduce(Decimal(0)) { $0 + $1.budget }
                    HStack {
                        Text("Total")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text("\(budgetEuros(spent)) / \(budgetEuros(available))")
                            .font(theme.captionFont)
                            .monospacedDigit()
                            .foregroundStyle(spent > available ? theme.negative : theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .sheet(item: $editing) { EnvelopeEditorSheet(categoryID: $0.id, month: month) }
    }
}

/// Une enveloppe : jauge avec repère du rythme, reste, rythme possible et projection.
private struct EnvelopeRow: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let status: BudgetStatus
    let month: Date
    let isCurrent: Bool

    private var barColor: Color {
        switch status.state {
        case .ok: theme.color(for: status.category)
        case .warning: theme.warning
        case .exceeded: theme.negative
        }
    }

    private var projected: Decimal? { store.projectedSpending(for: status.category, month: month) }
    private var projectedOver: Bool { (projected ?? 0) > status.budget && status.state != .exceeded }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing) {
            CategoryBadge(category: status.category)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.category.label)
                        .font(theme.bodyFont)
                        .foregroundStyle(status.state == .exceeded ? theme.negative : theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: theme.spacing)
                    Text("\(budgetEuros(status.spent)) / \(budgetEuros(status.budget))")
                        .font(theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(status.state == .exceeded ? theme.negative : theme.textSecondary)
                        .lineLimit(1)
                }
                gauge
                if status.state == .exceeded {
                    Text("Dépassé de \(budgetEuros(status.overspent))")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.negative)
                } else {
                    Text(remainingText)
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                if let projected {
                    Text("Fin de mois estimée : \(budgetEuros(projected))")
                        .font(theme.captionFont)
                        .foregroundStyle(projectedOver ? theme.warning : theme.textSecondary)
                }
                chips
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var remainingText: String {
        var text = "Reste \(budgetEuros(status.remaining))"
        let days = BudgetStore.daysRemaining(in: month)
        if isCurrent, days > 0 {
            text += " · \(budgetEuros(status.remaining / Decimal(days))) / jour possible"
        }
        return text
    }

    /// Jauge de consommation, avec un repère vertical sur la part du mois écoulée.
    private var gauge: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2).fill(theme.surfaceSecondary)
                RoundedRectangle(cornerRadius: theme.smallCornerRadius / 2).fill(barColor)
                    .frame(width: geo.size.width * min(1, max(0, status.ratio)))
                if isCurrent {
                    let x = geo.size.width * min(1, max(0, BudgetStore.elapsedFraction(of: month)))
                    Capsule().fill(theme.textPrimary.opacity(0.7))
                        .frame(width: 2, height: 11)
                        .offset(x: min(max(0, x - 1), geo.size.width - 2))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 11)
    }

    @ViewBuilder private var chips: some View {
        let hasChips = status.carryOver != 0 || store.hasBudgetOverride(for: status.category, month: month)
        if hasChips {
            HStack(spacing: 6) {
                if status.carryOver != 0 {
                    let amount = budgetEuros(abs(status.carryOver))
                    chip(status.carryOver > 0 ? "+\(amount) reportés" : "−\(amount) reportés",
                         color: status.carryOver > 0 ? theme.positive : theme.negative)
                }
                if store.hasBudgetOverride(for: status.category, month: month) {
                    chip("Budget de ce mois", color: theme.accent)
                }
            }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(theme.captionFont)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Éditeur de budget : par défaut, propre au mois, report, retrait.
private struct EnvelopeEditorSheet: View {
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

    var body: some View {
        let suggestions = store.budgetSuggestions()
        if !suggestions.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    HStack {
                        Text("Suggestions")
                            .font(theme.titleFont)
                            .foregroundStyle(theme.textPrimary)
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
            }
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
