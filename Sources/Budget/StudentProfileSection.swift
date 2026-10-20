import SwiftUI

// Profil étudiant : réglage, aides et questions de l'assistant de démarrage.

extension AccountKind {
    /// Types sans banque associée (espèces, Izly).
    var hidesBank: Bool { self == .cash || self == .izly }

    /// Types proposables dans une famille : Izly seulement pour un étudiant (ou si déjà utilisé).
    static func selectableKinds(in family: AccountFamily, studentEnabled: Bool, current: AccountKind? = nil) -> [AccountKind] {
        kinds(in: family).filter { $0 != .izly || studentEnabled || current == .izly }
    }
}

extension Account {
    /// Compte Izly neuf, sur la première couleur de palette non utilisée.
    @MainActor static func makeIzly(id: String = UUID().uuidString, balance: Decimal = 0,
                                    existing: [Account], paletteCount: Int) -> Account {
        let count = max(paletteCount, 1)
        let used = Set(existing.map(\.colorIndex))
        let color = (0..<count).first { !used.contains($0) } ?? existing.count % count
        var account = Account(id: id, name: "Izly", kind: .izly, colorIndex: color, initialBalance: balance)
        account.mealPlan = MealPlan() // repas automatiques activés par défaut
        return account
    }
}

/// Section « Profil » des Réglages.
struct StudentProfileSection: View {
    @AppStorage(StudentProfile.enabledKey) private var isStudent = false
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme

    private var hasIzly: Bool { store.accounts.contains { $0.kind == .izly } }

    var body: some View {
        Section {
            Toggle("Je suis étudiant", isOn: $isStudent)
            if isStudent && !hasIzly {
                Button {
                    store.upsertAccount(.makeIzly(existing: store.accounts, paletteCount: theme.categoryPalette.count))
                } label: {
                    Label("Ajouter mon compte Izly", systemImage: "plus.circle.fill")
                        .foregroundStyle(theme.accent)
                }
            }
        } header: {
            Text("Profil")
        } footer: {
            Text("Active le compte Izly et les repas Crous.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
        }
    }
}

/// Étape « Es-tu étudiant ? » de l'assistant.
struct OnboardingStudentStep: View {
    @Environment(\.theme) private var theme
    @Binding var isStudent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            OnboardingStepHeader(
                title: "Es-tu étudiant ?",
                subtitle: "Si oui, on prépare un compte Izly et un ajout rapide pour tes repas Crous (1 €).")
            Card {
                EditorFlowLayout(spacing: theme.spacing) {
                    OnboardingChip(title: "Oui", icon: "graduationcap.fill", selected: isStudent) { isStudent = true }
                    OnboardingChip(title: "Non", selected: !isStudent) { isStudent = false }
                }
            }
        }
    }
}

/// Carte « Compte Izly » de l'étape des comptes.
struct OnboardingIzlyCard: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool
    @Binding var balanceText: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                HStack(spacing: theme.spacing) {
                    OnboardingCheck(isOn: $isOn)
                    Image(systemName: AccountKind.izly.icon).foregroundStyle(theme.accent)
                    Text("Compte Izly").foregroundStyle(theme.textPrimary)
                    Spacer()
                    if isOn {
                        OnboardingNumberField(title: "Solde actuel", text: $balanceText, unit: "€", width: 90)
                    }
                }
                Text("Ton porte-monnaie Crous, alimenté par des virements. Solde actuel facultatif.")
                    .font(theme.captionFont).foregroundStyle(theme.textSecondary)
            }
        }
    }
}
