import SwiftUI

/// Plan du mois : revenus − charges fixes − enveloppes − épargne = reste à répartir, puis le réalisé.
struct MonthPlanCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date

    @State private var showFixed = false
    @State private var showEditor = false

    private static let dayFormat = Date.FormatStyle().day().month(.abbreviated)

    var body: some View {
        let plan = store.monthPlan(month: month)
        Card {
            VStack(alignment: .leading, spacing: theme.spacing * 1.25) {
                header(plan)
                if plan.incomeSource == .none && plan.savingsGoal == 0 && plan.envelopes == 0 && plan.fixedCharges.isEmpty {
                    prompt
                } else {
                    cascade(plan)
                    if plan.expectedIncome > 0 { stackedBar(plan) }
                    Divider().overlay(theme.separator)
                    actual(plan)
                }
            }
        }
        .sheet(isPresented: $showEditor) { BudgetPlanEditor() }
    }

    private func header(_ plan: MonthPlan) -> some View {
        HStack {
            Text("Plan du mois")
                .font(theme.titleFont)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button("Modifier") { showEditor = true }
                .buttonStyle(.plain)
                .font(theme.bodyFont.weight(.semibold))
                .foregroundStyle(theme.accent)
                .accessibilityHint("Modifier l'objectif d'épargne et les revenus prévus")
        }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            Text("Renseigne tes revenus prévus et, si tu veux, un objectif d'épargne : tu verras ce qu'il te reste à répartir chaque mois.")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
            Button("Renseigner mes revenus") { showEditor = true }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
    }

    // MARK: - Cascade

    private func cascade(_ plan: MonthPlan) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing * 0.75) {
            line("Revenus prévus", plan.expectedIncome, sign: "", tint: theme.positive, detail: plan.incomeSource.label)
            if plan.fixedCharges.isEmpty {
                line("Charges fixes", plan.fixedTotal, sign: "−", tint: theme.textPrimary)
            } else {
                Button {
                    withAnimation(.snappy) { showFixed.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(theme.captionFont.bold())
                            .rotationEffect(.degrees(showFixed ? 90 : 0))
                            .foregroundStyle(theme.textTertiary)
                        line("Charges fixes", plan.fixedTotal, sign: "−", tint: theme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(showFixed ? "Masquer le détail" : "Afficher le détail")
                if showFixed {
                    VStack(spacing: 6) {
                        ForEach(plan.fixedCharges) { charge in
                            HStack {
                                Text(charge.name).lineLimit(1)
                                Spacer()
                                Text(charge.date.formatted(Self.dayFormat)).foregroundStyle(theme.textTertiary)
                                Text(budgetEuros(charge.amount)).frame(minWidth: 70, alignment: .trailing)
                            }
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
            line("Enveloppes", plan.envelopes, sign: "−", tint: theme.textPrimary, detail: "Budgets des catégories")
            line("Épargne visée", plan.savingsGoal, sign: "−", tint: theme.textPrimary)
            Divider().overlay(theme.separator)
            let rest = plan.unallocated
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Reste à répartir")
                        .font(theme.bodyFont.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(budgetEuros(rest))
                        .font(theme.amountFont)
                        .foregroundStyle(rest >= 0 ? theme.positive : theme.negative)
                }
                Text(rest >= 0 ? "à répartir dans tes enveloppes ou ton épargne"
                                : "ton plan dépasse tes revenus de \(budgetEuros(-rest))")
                    .font(theme.captionFont)
                    .foregroundStyle(rest >= 0 ? theme.textSecondary : theme.negative)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func line(_ title: String, _ amount: Decimal, sign: String, tint: Color, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(theme.bodyFont).foregroundStyle(theme.textPrimary)
                if let detail {
                    Text(detail).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
            Text("\(sign)\(sign.isEmpty ? "" : " ")\(budgetEuros(amount))")
                .font(theme.amountFont)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Barre empilée

    private func stackedBar(_ plan: MonthPlan) -> some View {
        let income = plan.expectedIncome.doubleValue
        let rest = max(0, plan.unallocated)
        let parts: [(String, Decimal, Color)] = [
            ("Charges fixes", plan.fixedTotal, theme.textTertiary),
            ("Enveloppes", plan.envelopes, theme.accent),
            ("Épargne", plan.savingsGoal, theme.positive),
            ("Reste", rest, theme.surfaceSecondary),
        ]
        // Si le plan dépasse les revenus, la barre est répartie sur le total du plan.
        let total = max(income, parts.reduce(0) { $0 + $1.1.doubleValue })
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts.indices, id: \.self) { i in
                        let share = total > 0 ? parts[i].1.doubleValue / total : 0
                        if share > 0 {
                            RoundedRectangle(cornerRadius: 3).fill(parts[i].2)
                                .frame(width: max(2, (geo.size.width - 6) * share))
                        }
                    }
                }
            }
            .frame(height: 12)
            .clipShape(.rect(cornerRadius: theme.smallCornerRadius))
            HStack(spacing: theme.spacing) {
                ForEach(parts.indices, id: \.self) { i in
                    if parts[i].1 > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(parts[i].2).frame(width: 8, height: 8)
                            Text(parts[i].0).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Répartition des revenus prévus : "
            + parts.filter { $0.1 > 0 }.map { "\($0.0) \(budgetEuros($0.1))" }.joined(separator: ", "))
    }

    // MARK: - Réalisé

    private func actual(_ plan: MonthPlan) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing * 0.75) {
            Text("Réalisé")
                .font(theme.bodyFont.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            row("Revenus reçus", "\(budgetEuros(plan.actualIncome)) / \(budgetEuros(plan.expectedIncome))")
            row("Dépensé", budgetEuros(plan.actualSpent))
            row("Épargne réelle", budgetEuros(plan.actualSavings),
                tint: plan.actualSavings >= 0 ? theme.positive : theme.negative)
            if plan.savingsGoal > 0 {
                let progress = min(max(plan.actualSavings.doubleValue / plan.savingsGoal.doubleValue, 0), 1)
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)
                        .tint(plan.actualSavings >= plan.savingsGoal ? theme.positive : theme.accent)
                    Text("\(Int((progress * 100).rounded())) % de ton objectif de \(budgetEuros(plan.savingsGoal))")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            if plan.unbudgetedSpent > 0 {
                row("Dépenses hors budget", budgetEuros(plan.unbudgetedSpent))
            }
        }
    }

    private func row(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(title).font(theme.bodyFont).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).font(theme.bodyFont.weight(.medium)).foregroundStyle(tint ?? theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feuille d'édition

/// Édition de l'objectif d'épargne et des revenus prévus.
private struct BudgetPlanEditor: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var savingsText = ""
    @State private var incomeText = ""
    @State private var autoIncome = true

    /// Montant saisi (virgule acceptée) : nil si vide ou invalide, doit être > 0.
    private func parse(_ raw: String) -> Decimal? {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: text), value > 0 else { return nil }
        return value
    }

    private func isValid(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespaces).isEmpty || parse(raw) != nil
    }

    private var canSave: Bool {
        isValid(savingsText) && (autoIncome || parse(incomeText) != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Objectif d'épargne mensuel", text: $savingsText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .accessibilityLabel("Objectif d'épargne mensuel en euros")
                } footer: {
                    Text(isValid(savingsText) ? "Laisse vide pour ne pas viser d'épargne." : "Saisis un montant supérieur à 0.")
                        .foregroundStyle(isValid(savingsText) ? theme.textSecondary : theme.negative)
                }
                Section {
                    Toggle("Estimer automatiquement", isOn: $autoIncome)
                    if !autoIncome {
                        TextField("Revenus prévus par mois", text: $incomeText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityLabel("Revenus prévus par mois en euros")
                    }
                } header: {
                    Text("Revenus prévus")
                } footer: {
                    if autoIncome {
                        Text("Calculés d'après tes revenus récurrents, sinon la moyenne des 3 derniers mois.")
                            .foregroundStyle(theme.textSecondary)
                    } else if !incomeText.trimmingCharacters(in: .whitespaces).isEmpty && parse(incomeText) == nil {
                        Text("Saisis un montant supérieur à 0.").foregroundStyle(theme.negative)
                    }
                }
            }
            .navigationTitle("Plan du mois")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        store.setBudgetPlan(BudgetPlan(savingsGoal: parse(savingsText),
                                                       expectedIncome: autoIncome ? nil : parse(incomeText)))
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .onAppear {
            let plan = store.budgetPlan
            savingsText = plan.savingsGoal.map { "\($0)".replacingOccurrences(of: ".", with: ",") } ?? ""
            if let income = plan.expectedIncome {
                autoIncome = false
                incomeText = "\(income)".replacingOccurrences(of: ".", with: ",")
            }
        }
    }
}
