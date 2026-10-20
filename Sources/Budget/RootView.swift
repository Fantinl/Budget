import SwiftUI

/// Écran racine : barre latérale (sections et comptes) et détail.
struct RootView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var selection: SidebarItem = .dashboard
    /// Assistant de démarrage terminé (affiché au premier lancement, relançable depuis les réglages).
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    /// Relevé déposé sur la fenêtre (glisser-déposer) et survol en cours.
    @State private var droppedStatement: DroppedStatement?
    @State private var isDropTargeted = false
    /// Compte Izly dont la revue hebdomadaire des repas est proposée au lancement.
    @State private var mealReview: MealReviewTarget?

    private struct DroppedStatement: Identifiable {
        let id = UUID()
        let url: URL
    }

    private static let statementExtensions: Set<String> = ["csv", "ofx", "qfx", "txt", "xlsx", "xls"]

    var body: some View {
        // Barre latérale toujours visible (pas de bouton pour la replier).
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                #if os(macOS)
                // Réglages accessibles depuis toutes les pages
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Réglages", systemImage: "gearshape") { openSettings() }
                            .help("Réglages (⌘,)")
                    }
                }
                #endif
        }
        .tint(theme.accent)
        .fontDesign(theme.fontDesign)
        .bindsUndoToStore()
        .dropDestination(for: URL.self) { urls, _ in
            guard onboardingCompleted,
                  let url = urls.first(where: { Self.statementExtensions.contains($0.pathExtension.lowercased()) })
            else { return false }
            droppedStatement = DroppedStatement(url: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay { if isDropTargeted { dropVeil } }
        .animation(.smooth(duration: 0.15), value: isDropTargeted)
        .sheet(item: $mealReview) { target in
            MealReviewSheet(accountID: target.id)
        }
        .sheet(item: $droppedStatement) { dropped in
            ImportStatementView(initialURL: dropped.url)
        }
        .sheet(isPresented: Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })) {
            OnboardingView { onboardingCompleted = true }
                .interactiveDismissDisabled()
        }
        .task {
            // Au lancement : sauvegarde du jour, puis échéances récurrentes passées.
            store.backupIfNeeded()
            store.generateDueRecurringOperations()
            store.generateDueMeals() // repas Izly décomptés automatiquement
            // Revue hebdomadaire des repas (pas pendant l'assistant de démarrage)
            if onboardingCompleted, let account = store.needsMealReview() {
                mealReview = MealReviewTarget(id: account.id)
            }
            await store.refreshRates() // taux des livrets réglementés (au plus une fois par semaine)
        }
    }

    /// Voile affiché pendant le survol d'un fichier.
    private var dropVeil: some View {
        ZStack {
            theme.background.opacity(0.8)
            VStack(spacing: theme.spacing) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: theme.iconSize, weight: .light))
                    .foregroundStyle(theme.accent)
                Text("Dépose ton relevé pour l’importer")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(theme.padding * 2)
            .background(theme.surface, in: .rect(cornerRadius: theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius)
                .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .dashboard:
            DashboardView { selection = $0 }
        case .operations:
            ContentView()
        case .accounts:
            AccountsView()
        case .stats:
            StatsView(accountID: nil)
        }
    }
}

/// Cible de la feuille de revue des repas (identifiant du compte Izly).
private struct MealReviewTarget: Identifiable {
    let id: String
}
