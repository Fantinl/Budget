#if os(macOS)
import Sparkle
import SwiftUI

/// Mises à jour automatiques via Sparkle : l'app lit appcast.xml (dépôt GitHub), télécharge
/// la nouvelle version depuis la release GitHub, vérifie sa signature puis l'installe.
@MainActor
final class AppUpdater: ObservableObject {
    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published var canCheckForUpdates = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

/// Entrée de menu « Rechercher des mises à jour… » (menu Budget).
struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button("Rechercher des mises à jour…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}
#endif
