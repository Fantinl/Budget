import SwiftUI

/// Récurrente proposée (ou personnalisée) pendant l'assistant.
struct OnboardingRecurringItem: Identifiable {
    let id = UUID()
    var name: String
    var categoryID: String
    var kind: TransactionKind
    var amountText: String
    var dayText: String
    var selected = false
    var isCustom = false

    init(name: String, categoryID: String, kind: TransactionKind = .expense, amount: Decimal, day: Int, isCustom: Bool = false) {
        self.name = name
        self.categoryID = categoryID
        self.kind = kind
        amountText = OnboardingFormat.text(amount)
        dayText = String(day)
        self.isCustom = isCustom
        selected = isCustom
    }

    static let suggestions: [OnboardingRecurringItem] = [
        .init(name: "Loyer", categoryID: "housing", amount: 800, day: 5),
        .init(name: "Salaire", categoryID: "salary", kind: .income, amount: 2000, day: 28),
        .init(name: "Électricité", categoryID: "housing", amount: 60, day: 10),
        .init(name: "Internet / box", categoryID: "housing", amount: 30, day: 12),
        .init(name: "Forfait mobile", categoryID: "subscriptions", amount: 15, day: 15),
        .init(name: "Assurance habitation", categoryID: "housing", amount: 20, day: 8),
        .init(name: "Netflix / Spotify", categoryID: "subscriptions", amount: 10, day: 15),
        .init(name: "Transport (pass Navigo)", categoryID: "transport", amount: 90.80, day: 1),
    ]

    var amount: Decimal? { OnboardingFormat.positive(amountText) }
    var day: Int? { Int(dayText.trimmingCharacters(in: .whitespaces)).flatMap { (1...31).contains($0) ? $0 : nil } }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var isValid: Bool { !trimmedName.isEmpty && amount != nil && day != nil }

    /// Première date (aujourd'hui ou plus tard) tombant le jour choisi ; pas d'échéance passée.
    static func nextDate(day: Int, from now: Date = .now) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let month = calendar.dateInterval(of: .month, for: today)?.start else { return today }
        var fallback = today
        for offset in 0..<14 {
            guard let target = calendar.date(byAdding: .month, value: offset, to: month),
                  let range = calendar.range(of: .day, in: .month, for: target),
                  let date = calendar.date(byAdding: .day, value: min(day, range.count) - 1, to: target),
                  date >= today else { continue }
            if range.count >= day { return date }
            if fallback == today { fallback = date }
        }
        return fallback
    }
}

struct OnboardingRecurringStep: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Binding var items: [OnboardingRecurringItem]

    /// Noms déjà couverts par une récurrente existante.
    private var existingNames: Set<String> {
        Set(store.recurringOperations.map { $0.name.lowercased() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            OnboardingStepHeader(
                title: "Opérations récurrentes",
                subtitle: "Loyer, salaire, abonnements… Coche ce qui revient chaque mois : elles seront ajoutées automatiquement à partir de la prochaine échéance. Facultatif.")

            if !store.recurringOperations.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: theme.spacing) {
                        Text("Déjà configurées").font(theme.captionFont).foregroundStyle(theme.textSecondary)
                        ForEach(store.recurringOperations) { operation in
                            HStack(spacing: theme.spacing) {
                                CategoryBadge(category: store.category(id: operation.categoryID), size: 30)
                                Text(operation.name).font(theme.bodyFont).foregroundStyle(theme.textPrimary)
                                Spacer()
                                Text(operation.amount.euros).font(theme.amountFont).foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    ForEach($items) { $item in
                        if item.isCustom || !existingNames.contains(item.name.lowercased()) {
                            row($item)
                            Divider().overlay(theme.separator)
                        }
                    }
                    Button {
                        items.append(OnboardingRecurringItem(name: "", categoryID: Self.fallback, amount: 0, day: 1, isCustom: true))
                        items[items.count - 1].amountText = ""
                    } label: {
                        Label("Ajouter une opération", systemImage: "plus.circle.fill")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.accent)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let fallback = BudgetStore.fallbackID(for: .expense)

    private func row(_ item: Binding<OnboardingRecurringItem>) -> some View {
        let value = item.wrappedValue
        let category = store.category(id: value.categoryID)
        return HStack(spacing: theme.spacing) {
            OnboardingCheck(isOn: item.selected)
            CategoryBadge(category: category, size: 30)
            if value.isCustom {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Nom", text: item.name, prompt: Text("Nom de l'opération"))
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.textPrimary)
                    HStack(spacing: theme.spacing) {
                        Picker("Type", selection: item.kind) {
                            ForEach(TransactionKind.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: value.kind) { _, kind in
                            item.wrappedValue.categoryID = store.fallbackCategory(for: kind).id
                        }
                        Picker("Catégorie", selection: item.categoryID) {
                            ForEach(store.categories(for: value.kind)) { Text($0.label).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.name).font(theme.bodyFont).foregroundStyle(theme.textPrimary)
                    Text(category.label).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            OnboardingNumberField(title: "Montant", text: item.amountText, unit: "€")
            HStack(spacing: 4) {
                Text("le").foregroundStyle(theme.textSecondary).font(theme.bodyFont)
                OnboardingNumberField(title: "Jour du mois", text: item.dayText, unit: "", width: 28)
            }
        }
        .opacity(value.selected ? 1 : 0.7)
    }
}
