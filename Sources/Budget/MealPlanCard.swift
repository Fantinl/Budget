import SwiftUI

/// Carte « Repas automatiques » du compte Izly.
struct MealPlanCard: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme

    let accountID: String
    @State private var priceText = ""
    @State private var loaded = false
    @State private var showReview = false
    @State private var showPeriod = false

    private var account: Account { store.account(id: accountID) }
    private var plan: MealPlan { account.mealPlan ?? MealPlan(isEnabled: false) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.padding) {
                Toggle(isOn: binding(\.isEnabled)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repas automatiques").font(theme.titleFont).foregroundStyle(theme.textPrimary)
                        Text("Un repas décompté chaque jour choisi.")
                            .font(theme.captionFont).foregroundStyle(theme.textSecondary)
                    }
                }
                if plan.isEnabled {
                    HStack {
                        Text("Prix du repas").foregroundStyle(theme.textPrimary)
                        Spacer()
                        TextField("Prix", text: $priceText, prompt: Text("1,00").foregroundStyle(theme.textTertiary))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: priceText) { _, text in
                                if let value = parseMealPrice(text), value != plan.price { update { $0.price = value } }
                            }
                        Text("€").foregroundStyle(theme.textSecondary)
                    }
                    .font(theme.bodyFont)
                    VStack(alignment: .leading, spacing: theme.spacing / 2) {
                        Text("Jours").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                        MealWeekdayPicker(weekdays: binding(\.weekdays))
                    }
                    DatePicker("À partir du", selection: binding(\.startDate), displayedComponents: .date)
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                }
                HStack(spacing: theme.spacing) {
                    if plan.isEnabled {
                        Button("Revue de la semaine", systemImage: "checklist") { showReview = true }
                    }
                    Button("Ajouter des repas sur une période…", systemImage: "calendar.badge.plus") { showPeriod = true }
                }
                .font(theme.captionFont)
                .disabled(account.isArchived)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            priceText = plan.price.formatted(.number.precision(.fractionLength(0...2)))
        }
        .sheet(isPresented: $showReview) { MealReviewSheet(accountID: accountID) }
        .sheet(isPresented: $showPeriod) { MealPeriodSheet(accountID: accountID) }
    }

    /// Modifie le plan puis enregistre le compte.
    private func update(_ change: (inout MealPlan) -> Void) {
        var account = account
        var plan = account.mealPlan ?? MealPlan()
        change(&plan)
        account.mealPlan = plan
        store.upsertAccount(account)
        if plan.isEnabled { store.generateDueMeals() }
    }

    private func binding<Value: Equatable>(_ keyPath: WritableKeyPath<MealPlan, Value>) -> Binding<Value> {
        Binding(get: { plan[keyPath: keyPath] }, set: { new in
            guard new != plan[keyPath: keyPath] else { return }
            update { $0[keyPath: keyPath] = new }
        })
    }
}
