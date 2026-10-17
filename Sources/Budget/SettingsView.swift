import SwiftUI

/// Écran de réglages : catégories, dépenses rapides, apparence.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @Environment(BudgetStore.self) private var store
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var showShortcuts = false
    #endif

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
                    Button {
                        #if os(macOS)
                        openWindow(id: "shortcuts")
                        #else
                        showShortcuts = true
                        #endif
                    } label: {
                        Label("Raccourcis clavier", systemImage: "keyboard")
                    }
                }
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
            #if os(iOS)
            .sheet(isPresented: $showShortcuts) {
                NavigationStack {
                    ShortcutsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("OK") { showShortcuts = false } }
                        }
                }
            }
            #endif
        }
    }
}
