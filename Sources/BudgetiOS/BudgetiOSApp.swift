import SwiftUI

@main
struct BudgetiOSApp: App {
    @State private var store: BudgetStore
    @State private var coordinator: SyncCoordinator
    /// Thème choisi dans les réglages (identifiant d'un `Theme` de `Theme.all`).
    @AppStorage("themeID") private var themeID = Theme.current.id
    /// Clair / sombre / automatique, choisi dans les réglages.
    @AppStorage("appearance") private var appearance = AppearanceMode.system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = BudgetStore()
        _store = State(initialValue: store)
        _coordinator = State(initialValue: SyncCoordinator(store: store))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(store)
                .environment(coordinator)
                .environment(\.theme, Theme.named(themeID))
                .preferredColorScheme(appearance.colorScheme)
                .task { coordinator.start() }
        }
        .onChange(of: scenePhase) { _, phase in coordinator.handleScenePhase(phase) }
    }
}
