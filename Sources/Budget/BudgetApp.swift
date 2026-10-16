import SwiftUI

@main
struct BudgetApp: App {
    @State private var store = BudgetStore()
    /// Thème choisi dans les réglages (identifiant d'un `Theme` de `Theme.all`).
    @AppStorage("themeID") private var themeID = Theme.current.id
    /// Clair / sombre / automatique, choisi dans les réglages.
    @AppStorage("appearance") private var appearance = AppearanceMode.system

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.theme, Theme.named(themeID))
                #if os(macOS)
                .frame(minWidth: 460, minHeight: 560)
                // Sur Mac, `preferredColorScheme(nil)` ne revient pas toujours au mode du système :
                // on règle l'apparence de toute l'app à la place.
                .onAppear { NSApp.appearance = appearance.nsAppearance }
                .onChange(of: appearance) { _, mode in NSApp.appearance = mode.nsAppearance }
                #else
                .preferredColorScheme(appearance.colorScheme)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 820, height: 780)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(store)
                .environment(\.theme, Theme.named(themeID))
                .frame(minWidth: 560, minHeight: 640)
        }
        #endif
    }
}
