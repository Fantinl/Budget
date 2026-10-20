import Foundation
import Observation
import SwiftUI

/// Orchestre la synchronisation : lire le distant, fusionner, appliquer au magasin, réécrire.
/// À brancher (voir plus bas) : `start()` au lancement, `handleScenePhase(_:)` sur `scenePhase`,
/// et `.environment(coordinator)` pour la vue Réglages → Synchronisation.
@MainActor
@Observable
final class SyncCoordinator {
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var folderName: String?
    var isConfigured: Bool { transport != nil }

    /// Délai après une modification locale, et période de la synchro périodique.
    @ObservationIgnored var debounceInterval: TimeInterval = 3
    @ObservationIgnored var periodicInterval: TimeInterval = 120

    @ObservationIgnored private let store: BudgetStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var transport: (any SyncTransport)?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var periodicTask: Task<Void, Never>?
    @ObservationIgnored private var resyncRequested = false

    private static let lastSyncKey = "syncLastDate"

    /// `transport` permet d'injecter un autre transport (tests, futur serveur) ; sinon on utilise le signet enregistré.
    init(store: BudgetStore, defaults: UserDefaults = .standard, transport: (any SyncTransport)? = nil) {
        self.store = store
        self.defaults = defaults
        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date
        if let transport {
            self.transport = transport
        } else if let url = SyncFolderBookmark.resolve(defaults: defaults) {
            self.transport = FolderSyncTransport(folderURL: url)
            folderName = url.lastPathComponent
        } else if defaults.data(forKey: SyncFolderBookmark.defaultsKey) != nil {
            lastError = SyncError.folderUnavailable.errorDescription
        }
        store.sync.onLocalChange = { [weak self] in self?.scheduleSync() }
    }

    /// Vrai si l'URL est dans le conteneur privé de l'app (Documents, Application Support…).
    static func isAppPrivateFolder(_ url: URL) -> Bool {
        let container = URL.homeDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        #if os(iOS)
        return path.hasPrefix(container)
        #else
        // Sur Mac, l'app n'est pas isolée : seul son propre dossier de données est exclu.
        let own = BudgetStore.defaultDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(own)
        #endif
    }

    // MARK: - Configuration

    /// Mémorise le dossier choisi dans le sélecteur de fichiers et lance une première synchro.
    func chooseFolder(_ url: URL) async {
        // Le dossier doit être partagé entre les appareils : pas le dossier privé de l'app
        // (« Sur mon iPhone → Budget » dans Fichiers), que l'autre appareil ne voit jamais.
        if Self.isAppPrivateFolder(url) {
            lastError = "Ce dossier est privé à cet appareil. Choisis le dossier « Budget » dans iCloud Drive (pas « Sur mon iPhone »)."
            return
        }
        do {
            try SyncFolderBookmark.save(url, defaults: defaults)
        } catch {
            lastError = "Ce dossier n'a pas pu être mémorisé : \(error.localizedDescription)"
            return
        }
        transport = FolderSyncTransport(folderURL: url)
        folderName = url.lastPathComponent
        lastError = nil
        store.sync.persist(to: store.syncMetaURL)
        await syncNow()
        startPeriodic()
    }

    /// Arrête la synchronisation (les données restent sur l'appareil ; le fichier du dossier n'est pas touché).
    func stop() {
        debounceTask?.cancel()
        periodicTask?.cancel()
        SyncFolderBookmark.clear(defaults: defaults)
        defaults.removeObject(forKey: Self.lastSyncKey)
        transport = nil
        folderName = nil
        lastSync = nil
        lastError = nil
    }

    // MARK: - Déclencheurs

    /// Au lancement de l'app.
    func start() { appDidBecomeActive() }

    func appDidBecomeActive() {
        guard isConfigured else { return }
        Task { await syncNow() }
        startPeriodic()
    }

    func appDidResignActive() {
        periodicTask?.cancel()
        periodicTask = nil
        debounceTask?.cancel()
        // Dernière chance de partir avec les modifications en attente.
        if isConfigured { Task { await syncNow() } }
    }

    /// À appeler depuis `.onChange(of: scenePhase)`.
    func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active { appDidBecomeActive() } else { appDidResignActive() }
    }

    /// Anti-rebond : synchronise après `debounceInterval` sans nouvelle modification.
    func scheduleSync() {
        guard isConfigured else { return }
        debounceTask?.cancel()
        let delay = debounceInterval
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func startPeriodic() {
        periodicTask?.cancel()
        let period = periodicInterval
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(period))
                guard !Task.isCancelled else { return }
                await self?.syncNow()
            }
        }
    }

    // MARK: - Synchronisation

    func syncNow() async {
        guard let transport else { return }
        if isSyncing {
            resyncRequested = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            resyncRequested = false
            do {
                try await runOnce(transport)
                lastError = nil
                lastSync = .now
                defaults.set(lastSync, forKey: Self.lastSyncKey)
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription
                    ?? "La synchronisation a échoué : \(error.localizedDescription)"
                return
            }
        } while resyncRequested
    }

    private func runOnce(_ transport: any SyncTransport) async throws {
        let remote = try await transport.read()
        // L'instantané local est pris après la lecture : on garde ce que l'utilisateur a fait pendant l'attente.
        let local = store.makeSyncSnapshot()
        let merged: SyncSnapshot
        if let remote, store.isSyncPristine {
            merged = remote   // appareil neuf : on adopte le distant (évite de dupliquer les valeurs par défaut)
        } else {
            merged = SyncMerge.merge(local: local, remote: remote ?? .empty)
        }
        store.applySyncSnapshot(merged)
        if remote == nil || !merged.sameContent(as: remote ?? .empty) {
            try await transport.write(merged)
        }
    }
}
