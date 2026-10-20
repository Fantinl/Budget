import SwiftUI

/// Revue hebdomadaire : « As-tu mangé au Crous ces jours-là ? »
struct MealReviewSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let accountID: String
    @State private var days: [Date] = []
    @State private var present: Set<Date> = []
    @State private var loaded = false
    @State private var showAdjust = false

    private var account: Account { store.account(id: accountID) }
    private var price: Decimal { account.mealPlan?.price ?? StudentProfile.defaultMealPrice }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.padding) {
                    Text("As-tu mangé au Crous ces jours-là ?")
                        .font(theme.titleFont)
                        .foregroundStyle(theme.textPrimary)
                    if days.isEmpty {
                        Text("Aucun jour à vérifier.")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textSecondary)
                    } else {
                        Card(padded: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                    if index > 0 { Divider().overlay(theme.separator) }
                                    dayRow(day)
                                }
                            }
                        }
                    }
                    Text(summary)
                        .font(theme.titleFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                    Button("Ajuster avec le solde réel…") { showAdjust = true }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
                .padding(theme.padding)
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle("Revue de la semaine")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Plus tard") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Valider", action: validate) }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showAdjust) { AdjustBalanceSheet(accountID: accountID) }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private var summary: String {
        let count = days.filter { present.contains($0) }.count
        return "\(count) repas · \((price * Decimal(count)).euros)"
    }

    private func dayRow(_ day: Date) -> some View {
        let isOn = present.contains(day)
        return Button {
            if isOn { present.remove(day) } else { present.insert(day) }
        } label: {
            HStack(spacing: theme.spacing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? theme.accent : theme.textTertiary)
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, theme.padding)
            .padding(.vertical, theme.spacing)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        days = store.mealReviewDays(of: account)
        let calendar = Calendar.current
        let interval = days.first.flatMap { first in
            days.last.flatMap { last in
                calendar.date(byAdding: .day, value: 1, to: last).map { DateInterval(start: first, end: $0) }
            }
        }
        guard let interval else { return }
        present = Set(store.meals(of: account, in: interval).map { calendar.startOfDay(for: $0.date) })
    }

    private func validate() {
        store.applyMealReview(account: account, days: days, present: present)
        dismiss()
    }
}
