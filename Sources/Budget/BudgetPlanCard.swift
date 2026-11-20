import SwiftUI

// MARK: - Feuille d'édition

/// Édition de l'objectif d'épargne et des revenus prévus.
struct BudgetPlanEditor: View {
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

// MARK: - Contenu de la section « Plan du mois »

/// Une soustraction simple : revenus prévus moins charges fixes, dépenses courantes et épargne visée.
struct MonthPlanCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store
    let month: Date
    @State private var showEditor = false

    var body: some View {
        let plan = store.monthPlan(month: month)
        let statuses = store.budgetStatuses(month: month)
        VStack(alignment: .leading, spacing: theme.spacing) {
            if plan.incomeSource == .none {
                Text("Indique tes revenus prévus pour voir ce qu'il reste à répartir.")
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
                Button("Prévoir mes revenus et mon épargne") { showEditor = true }
                    .buttonStyle(.plain)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.accent)
            } else {
                calculation(plan, statuses: statuses)
                HStack(spacing: 4) {
                    Text(plan.incomeSource.label)
                        .foregroundStyle(theme.textSecondary)
                    Button("Modifier") { showEditor = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                }
                .font(theme.captionFont)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showEditor) { BudgetPlanEditor() }
    }

    private func calculation(_ plan: MonthPlan, statuses: [BudgetStatus]) -> some View {
        let fixed = statuses.filter(\.isFixed).reduce(Decimal(0)) { $0 + $1.budget }
        let current = statuses.filter { !$0.isFixed }.reduce(Decimal(0)) { $0 + $1.budget }
        let rest = plan.unallocated
        return VStack(spacing: 6) {
            row("Revenus prévus", plan.expectedIncome)
            if fixed != 0 { row("− Charges fixes", fixed) }
            if current != 0 { row("− Dépenses courantes", current) }
            if plan.savingsGoal != 0 { row("− Épargne visée", plan.savingsGoal) }
            Divider()
            row(rest >= 0 ? "= Libre" : "= Manque", rest >= 0 ? rest : -rest,
                bold: true, color: rest >= 0 ? theme.textPrimary : theme.negative)
        }
    }

    private func row(_ label: String, _ amount: Decimal, bold: Bool = false, color: Color? = nil) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: theme.spacing)
            Text(wholeEuros(amount)).monospacedDigit()
        }
        .font(bold ? theme.bodyFont.bold() : theme.bodyFont)
        .foregroundStyle(color ?? theme.textPrimary)
    }
}
