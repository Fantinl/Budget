import SwiftUI

/// Feuille « Ajouter des repas sur une période » (du / au, jours, prix).
struct MealPeriodSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let accountID: String
    @State private var from = Calendar.current.startOfDay(for: .now)
    @State private var to = Calendar.current.startOfDay(for: .now)
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var priceText = ""
    @State private var loaded = false

    private var account: Account { store.account(id: accountID) }
    private var price: Decimal? { parseMealPrice(priceText) }
    private var count: Int { store.mealsToAdd(to: account, from: from, to: to, weekdays: weekdays) }
    private var canSave: Bool { price != nil && count > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.padding) {
                    Card {
                        VStack(alignment: .leading, spacing: theme.spacing) {
                            DatePicker("Du", selection: $from, displayedComponents: .date)
                            DatePicker("Au", selection: $to, in: from..., displayedComponents: .date)
                        }
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: theme.spacing) {
                            Text("Jours").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                            MealWeekdayPicker(weekdays: $weekdays)
                            HStack {
                                Text("Prix du repas").foregroundStyle(theme.textPrimary)
                                Spacer()
                                TextField("Prix", text: $priceText, prompt: Text("1,00").foregroundStyle(theme.textTertiary))
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Text("€").foregroundStyle(theme.textSecondary)
                            }
                            .font(theme.bodyFont)
                        }
                    }
                    Text(preview)
                        .font(theme.titleFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                    Text("Les jours déjà décomptés sont ignorés.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle("Ajouter des repas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter", action: save).disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }

    private var preview: String {
        let total = (price ?? 0) * Decimal(count)
        return "\(count) repas · \(total.euros)"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let plan = account.mealPlan {
            weekdays = plan.weekdays
            priceText = plan.price.formatted(.number.precision(.fractionLength(0...2)))
        } else {
            priceText = StudentProfile.defaultMealPrice.formatted(.number.precision(.fractionLength(0...2)))
        }
    }

    private func save() {
        guard let price, canSave else { return }
        store.addMeals(to: account, from: from, to: to, weekdays: weekdays, price: price)
        dismiss()
    }
}
