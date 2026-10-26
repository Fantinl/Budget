import SwiftUI

/// Racine iPhone : cinq onglets en bas (réglages derrière la roue de l'accueil), assistant de démarrage et tâches de lancement.
struct PhoneRootView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var tab: PhoneTab = .dashboard
    /// Assistant de démarrage terminé (affiché au premier lancement, relançable depuis les réglages).
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    /// Compte Izly dont la revue hebdomadaire des repas est proposée au lancement.
    @State private var mealReview: PhoneMealReviewTarget?
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                DashboardView { tab = PhoneTab(sidebar: $0) }
                    .navigationTitle("Accueil")
                    .toolbar {
                        Button { showSettings = true } label: { Label("Réglages", systemImage: "gearshape") }
                    }
            }
                .tabItem { Label("Accueil", systemImage: "square.grid.2x2") }
                .tag(PhoneTab.dashboard)
            ContentView()
                .tabItem { Label("Opérations", systemImage: "list.bullet") }
                .tag(PhoneTab.operations)
            AccountsView()
                .tabItem { Label("Comptes", systemImage: "building.columns") }
                .tag(PhoneTab.accounts)
            NavigationStack { BudgetPlanningView() }
                .tabItem { Label("Budget", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(PhoneTab.planning)
            NavigationStack { StatsView(accountID: nil).navigationTitle("Stats") }
                .tabItem { Label("Stats", systemImage: "chart.pie") }
                .tag(PhoneTab.stats)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .tint(theme.accent)
        .fontDesign(theme.fontDesign)
        .bindsUndoToStore()
        .sheet(item: $mealReview) { target in
            MealReviewSheet(accountID: target.id)
        }
        .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })) {
            OnboardingView { onboardingCompleted = true }
                .interactiveDismissDisabled()
        }
        #if DEBUG
        // Captures d'écran : `-debugTab N` au lancement choisit l'onglet.
        .onAppear {
            let all: [PhoneTab] = [.dashboard, .operations, .accounts, .planning, .stats]
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-debugTab"),
               let n = Int(ProcessInfo.processInfo.arguments[index + 1]), all.indices.contains(n) { tab = all[n] }
        }
        #endif
        .task {
            // Au lancement : sauvegarde du jour, puis échéances récurrentes passées.
            store.backupIfNeeded()
            store.generateDueRecurringOperations()
            store.generateDueMeals()
            if onboardingCompleted, let account = store.needsMealReview() {
                mealReview = PhoneMealReviewTarget(id: account.id)
            }
            await store.refreshRates()
        }
    }
}

private enum PhoneTab: Hashable {
    case dashboard, operations, accounts, planning, stats

    init(sidebar: SidebarItem) {
        switch sidebar {
        case .dashboard: self = .dashboard
        case .operations: self = .operations
        case .accounts: self = .accounts
        case .planning: self = .planning
        case .stats: self = .stats
        }
    }
}

private struct PhoneMealReviewTarget: Identifiable {
    let id: String
}
