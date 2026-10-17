import SwiftUI

@main
struct BudgetApp: App {
    @State private var store = BudgetStore()
    /// Thème choisi dans les réglages (identifiant d'un `Theme` de `Theme.all`).
    @AppStorage("themeID") private var themeID = Theme.current.id
    /// Clair / sombre / automatique, choisi dans les réglages.
    @AppStorage("appearance") private var appearance = AppearanceMode.system
    #if os(macOS)
    @StateObject private var updater = AppUpdater()
    /// Icône facultative dans la barre des menus (désactivée par défaut).
    @AppStorage(MenuBarSettings.enabled) private var menuBarEnabled = false
    #endif

    init() {
        #if os(macOS)
        MenuBarCoordinator.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
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
        .commands {
            #if os(macOS)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
            CommandGroup(before: .help) {
                ShortcutsHelpCommand()
            }
            #endif
            OperationsCommands()
        }

        #if os(macOS)
        Window("Raccourcis clavier", id: "shortcuts") {
            ShortcutsView()
                .environment(store)
                .environment(\.theme, Theme.named(themeID))
                .frame(minWidth: 460, minHeight: 480)
        }
        .defaultSize(width: 520, height: 680)

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarPanel()
                .environment(store)
                .environment(\.theme, Theme.named(themeID))
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
                .environment(\.theme, Theme.named(themeID))
                .frame(minWidth: 560, minHeight: 640)
        }
        #endif
    }
}
