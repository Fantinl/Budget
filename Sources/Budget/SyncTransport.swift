import Foundation

/// Transport d'un instantané : dossier iCloud Drive aujourd'hui, serveur perso demain.
/// La fusion (SyncMerge) ne dépend pas du transport.
protocol SyncTransport: Sendable {
    /// Dernier instantané publié, ou nil s'il n'y en a pas encore.
    func read() async throws -> SyncSnapshot?
    func write(_ snapshot: SyncSnapshot) async throws
}

// Étape 2 (plus tard) : `ServerSyncTransport: SyncTransport` — read() = GET de l'instantané,
// write() = PUT. Rien à changer dans SyncMerge ni SyncCoordinator.

enum SyncError: LocalizedError {
    case folderUnavailable
    case downloadTimeout
    case unreadable
    case newerFormat
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .folderUnavailable: "Le dossier de synchronisation est introuvable. Choisis-le à nouveau."
        case .downloadTimeout: "Le fichier de synchronisation n'a pas fini de se télécharger depuis iCloud. Réessaie dans un instant."
        case .unreadable: "Le fichier de synchronisation est illisible. Rien n'a été modifié."
        case .newerFormat: "Les données de synchronisation viennent d'une version plus récente de l'app. Mets cette app à jour."
        case .failed(let detail): "La synchronisation a échoué : \(detail)"
        }
    }
}

/// Échange via un fichier `Budget-sync.json` dans un dossier choisi par l'utilisateur (iCloud Drive).
struct FolderSyncTransport: SyncTransport {
    static let fileName = "Budget-sync.json"

    let folderURL: URL
    /// Durée maximale d'attente du téléchargement iCloud.
    var downloadTimeout: TimeInterval = 10

    var fileURL: URL { folderURL.appending(path: Self.fileName) }

    init(folderURL: URL, downloadTimeout: TimeInterval = 10) {
        self.folderURL = folderURL
        self.downloadTimeout = downloadTimeout
    }

    func read() async throws -> SyncSnapshot? {
        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        try await ensureDownloaded()
        guard let data = try coordinatedRead() else { return nil }
        guard let snapshot = try? SyncSnapshot.decoder.decode(SyncSnapshot.self, from: data) else {
            // Version plus récente dont le format ne se lit pas ? On le distingue d'un fichier cassé.
            if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data), probe.version > SyncSnapshot.currentVersion {
                throw SyncError.newerFormat
            }
            throw SyncError.unreadable
        }
        if snapshot.version > SyncSnapshot.currentVersion { throw SyncError.newerFormat }
        return snapshot
    }

    func write(_ snapshot: SyncSnapshot) async throws {
        let scoped = folderURL.startAccessingSecurityScopedResource()
        defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: folderURL.path) else { throw SyncError.folderUnavailable }
        let data = try SyncSnapshot.encoder.encode(snapshot)
        try coordinatedWrite(data)
    }

    private struct VersionProbe: Decodable { var version: Int }

    // MARK: - iCloud

    /// Si le fichier est dans iCloud mais pas encore sur l'appareil, demande le téléchargement et attend un peu.
    private func ensureDownloaded() async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folderURL.path) else { throw SyncError.folderUnavailable }
        // Toujours demander le téléchargement : sur iPhone, un fichier arrivé dans iCloud Drive
        // peut ne pas encore apparaître dans le dossier tant qu'il n'a pas été téléchargé.
        try? fm.startDownloadingUbiquitousItem(at: fileURL)
        let inICloud = (try? folderURL.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        let deadline = Date.now.addingTimeInterval(downloadTimeout)
        // Dossier iCloud sans fichier visible : on attend qu'il arrive ; s'il n'arrive pas,
        // c'est que personne n'a encore synchronisé (premier appareil).
        while inICloud && !fm.fileExists(atPath: fileURL.path) && Date.now < deadline {
            try? fm.startDownloadingUbiquitousItem(at: fileURL)
            try await Task.sleep(for: .milliseconds(250))
        }
        while needsDownload {
            if Date.now > deadline { throw SyncError.downloadTimeout }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private var needsDownload: Bool {
        let fm = FileManager.default
        let placeholder = folderURL.appending(path: ".\(Self.fileName).icloud")
        if fm.fileExists(atPath: placeholder.path) { return true }
        guard fm.fileExists(atPath: fileURL.path) else { return false }
        let status = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        return status != nil && status != .current
    }

    // MARK: - Coordination de fichiers

    private func coordinatedRead() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(SyncError.unreadable)
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private func coordinatedWrite(_ data: Data) throws {
        var coordinationError: NSError?
        var result: Result<Void, Error> = .success(())
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        try result.get()
    }
}

/// Signet « security-scoped » du dossier choisi, gardé dans UserDefaults.
enum SyncFolderBookmark {
    static let defaultsKey = "syncFolderBookmark"

    #if os(macOS)
    private static let createOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let resolveOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    private static let createOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    /// Crée et enregistre le signet d'un dossier choisi dans le sélecteur de fichiers.
    static func save(_ url: URL, defaults: UserDefaults = .standard) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: createOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: defaultsKey)
    }

    /// Résout le signet (et le renouvelle s'il est périmé). nil = aucun dossier ou dossier introuvable.
    static func resolve(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        if stale { try? save(url, defaults: defaults) }
        return url
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
