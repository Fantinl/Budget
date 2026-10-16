import SwiftUI

/// Écran de réglages : catégories, dépenses rapides, apparence.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @Environment(BudgetStore.self) private var store

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        SettingsCategoriesView()
                    } label: {
                        Label("Catégories", systemImage: "tag")
                    }
                    NavigationLink {
                        SettingsQuickExpensesView()
                    } label: {
                        Label("Dépenses rapides", systemImage: "bolt")
                    }
                    NavigationLink {
                        RecurringView()
                            .navigationTitle("Opérations récurrentes")
                    } label: {
                        Label("Opérations récurrentes", systemImage: "arrow.triangle.2.circlepath")
                    }
                    NavigationLink {
                        SettingsDataView()
                    } label: {
                        Label("Données", systemImage: "externaldrive")
                    }
                }
                Section {
                    Picker("Compte par défaut", selection: Binding(
                        get: { store.defaultAccount.id },
                        set: { id in if let account = store.activeAccounts.first(where: { $0.id == id }) { store.setDefaultAccount(account) } }
                    )) {
                        ForEach(store.activeAccounts) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Utilisé pour les nouvelles opérations, les ajouts rapides et les récurrentes sans compte précis.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                }
                SettingsAppearanceSection()
                Section {
                    Button("Relancer l'assistant de démarrage") { onboardingCompleted = false }
                }
            }
            .formStyle(.grouped)
            .font(theme.bodyFont)
            .tint(theme.accent)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Réglages")
            .bindsUndoToStore()
        }
    }
}
