import SwiftUI

/// Ajout rapide proposé (ou déjà existant) pendant l'assistant.
struct OnboardingQuickItem: Identifiable {
    let id = UUID()
    /// Ajout rapide existant, conservé tel quel (hors montant).
    var existing: QuickExpense?
    var name: String
    var categoryID: String
    var amountText: String
    var selected: Bool

    init(name: String, categoryID: String, amount: Decimal) {
        self.name = name
        self.categoryID = categoryID
        amountText = OnboardingFormat.text(amount)
        selected = false
    }

    init(existing: QuickExpense) {
        self.existing = existing
        name = existing.name
        categoryID = existing.categoryID
        amountText = OnboardingFormat.text(existing.amount)
        selected = true
    }

    static let suggestions: [OnboardingQuickItem] = [
        .init(name: "Café", categoryID: "restaurants", amount: 2.5),
        .init(name: "Boulangerie", categoryID: "groceries", amount: 3),
        .init(name: "Déjeuner", categoryID: "restaurants", amount: 12),
        .init(name: "Essence", categoryID: "transport", amount: 60),
        .init(name: "Courses", categoryID: "groceries", amount: 50),
        .init(name: "Tabac / presse", categoryID: "shopping", amount: 5),
        .init(name: "Parking", categoryID: "transport", amount: 3),
    ]

    var amount: Decimal? { OnboardingFormat.positive(amountText) }
    var isValid: Bool { !selected || amount != nil }

    @MainActor func quickExpense(store: BudgetStore) -> QuickExpense? {
        guard selected, let amount else { return nil }
        if var quick = existing {
            quick.amount = amount
            return quick
        }
        let known = store.categories.contains { $0.id == categoryID && !$0.isHidden && $0.kind == .expense }
        return QuickExpense(name: name, amount: amount,
                            categoryID: known ? categoryID : store.fallbackCategory(for: .expense).id)
    }
}

struct OnboardingQuickStep: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Binding var items: [OnboardingQuickItem]

    var body: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            OnboardingStepHeader(
                title: "Ajouts rapides",
                subtitle: "Des boutons pour saisir en un clic tes dépenses habituelles. Décoche ce qui ne te sert pas, ajuste les montants. Facultatif.")
            Card {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    ForEach($items) { $item in
                        let category = store.category(id: item.categoryID)
                        HStack(spacing: theme.spacing) {
                            OnboardingCheck(isOn: $item.selected)
                            CategoryBadge(category: category, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(theme.bodyFont).foregroundStyle(theme.textPrimary)
                                Text(category.label).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            OnboardingNumberField(title: "Montant", text: $item.amountText, unit: "€")
                        }
                        .opacity(item.selected ? 1 : 0.7)
                        if item.id != items.last?.id { Divider().overlay(theme.separator) }
                    }
                }
            }
        }
    }
}
