import SwiftUI

/// Écran racine : barre latérale (sections et comptes) et détail.
struct RootView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var selection: SidebarItem = .operations
    /// Assistant de démarrage terminé (affiché au premier lancement, relançable depuis les réglages).
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    /// Relevé déposé sur la fenêtre (glisser-déposer) et survol en cours.
    @State private var droppedStatement: DroppedStatement?
    @State private var isDropTargeted = false

    private struct DroppedStatement: Identifiable {
        let id = UUID()
        let url: URL
    }

    private static let statementExtensions: Set<String> = ["csv", "ofx", "qfx", "txt"]

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
        case .operations:
            ContentView()
        case .accounts:
            AccountsView()
        case .stats:
            StatsView(accountID: nil)
        }
    }
}
