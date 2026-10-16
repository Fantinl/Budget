import Foundation

/// Une sauvegarde sur disque : un dossier `Budget-2026-10-17_0930` contenant les deux fichiers JSON.
struct BackupInfo: Identifiable, Hashable {
    var url: URL
    var date: Date
    var size: Int64
    var transactionCount: Int?
    var id: URL { url }
}

/// Fichier de sauvegarde exporté / importé (un seul JSON combiné).
struct BackupBundle: Codable {
    var transactions: [Transaction]
    var settings: BudgetStore.Settings
}

extension BudgetStore {
    static let maxBackups = 30
    static let autoBackupInterval: TimeInterval = 24 * 3600

    var backupsDirectory: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }

    private var hasData: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: transactionsURL.path) || fm.fileExists(atPath: settingsURL.path)
    }

    // MARK: - Création

    /// Sauvegarde automatique : si la plus récente a plus de 24 h (ou s'il n'y en a pas) et qu'il y a des données.
    func backupIfNeeded(now: Date = .now) {
        guard hasData else { return }
        if let latest = listBackups().first, now.timeIntervalSince(latest.date) < Self.autoBackupInterval { return }
        createBackup(now: now)
    }

    /// Sauvegarde manuelle.
    @discardableResult
    func backupNow() -> Bool {
        guard hasData else {
            errorMessage = "Il n'y a encore aucune donnée à sauvegarder."
            return false
        }
        return createBackup(now: .now) != nil
    }

    /// Copie les deux fichiers dans un nouveau dossier, puis supprime les plus anciennes sauvegardes.
    @discardableResult
    private func createBackup(now: Date) -> URL? {
        let fm = FileManager.default
        let base = "Budget-" + Self.backupDateFormatter.string(from: now)
        var folder = backupsDirectory.appending(path: base, directoryHint: .isDirectory)
        var suffix = 2
        while fm.fileExists(atPath: folder.path) {
            folder = backupsDirectory.appending(path: "\(base)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for source in [transactionsURL, settingsURL] where fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: folder.appending(path: source.lastPathComponent))
            }
        } catch {
            try? fm.removeItem(at: folder)
            errorMessage = "La sauvegarde a échoué : \(error.localizedDescription)"
            return nil
        }
        for old in listBackups().dropFirst(Self.maxBackups) {
            try? fm.removeItem(at: old.url)
        }
        return folder
    }

    // MARK: - Liste

    /// Sauvegardes, de la plus récente à la plus ancienne.
    func listBackups() -> [BackupInfo] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]) else { return [] }
        return folders.compactMap { folder -> BackupInfo? in
            guard folder.lastPathComponent.hasPrefix("Budget-"),
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let name = String(folder.lastPathComponent.dropFirst("Budget-".count).prefix(15))
            let date = Self.backupDateFormatter.date(from: name)
                ?? (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                ?? .distantPast
            var size: Int64 = 0
            for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
                size += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            let count = (try? Data(contentsOf: folder.appending(path: "transactions.json")))
                .flatMap { try? Self.decoder.decode([Transaction].self, from: $0) }?.count
            return BackupInfo(url: folder, date: date, size: size, transactionCount: count)
        }
        .sorted { $0.date > $1.date }
    }

    // MARK: - Restauration

    /// Sauvegarde l'état actuel (pour pouvoir annuler), puis remplace les données par celles de la sauvegarde.
    @discardableResult
    func restore(_ backup: BackupInfo) -> Bool {
        let fm = FileManager.default
        let sources = [transactionsURL, settingsURL].map { backup.url.appending(path: $0.lastPathComponent) }
        // Vérifie que la sauvegarde est lisible avant de toucher aux données.
        do {
            if fm.fileExists(atPath: sources[0].path) { _ = try Self.decoder.decode([Transaction].self, from: Data(contentsOf: sources[0])) }
            if fm.fileExists(atPath: sources[1].path) { _ = try Self.decoder.decode(Settings.self, from: Data(contentsOf: sources[1])) }
        } catch {
            errorMessage = "Cette sauvegarde est illisible, la restauration est annulée. Vos données n'ont pas été modifiées."
            return false
        }
        if hasData, createBackup(now: .now) == nil { return false }
        do {
            for (source, destination) in zip(sources, [transactionsURL, settingsURL]) {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: destination) }
            }
        } catch {
            errorMessage = "La restauration a échoué : \(error.localizedDescription)"
            reloadFromDisk()
            return false
        }
        reloadFromDisk()
        return true
    }

    // MARK: - Export / import d'un fichier

    /// Contenu du fichier de sauvegarde combiné.
    func backupFileData() throws -> Data {
        let settings = Settings(categories: categories, quickExpenses: quickExpenses,
                                accounts: accounts, recurringOperations: recurringOperations,
                                defaultAccountID: defaultAccountID)
        return try Self.encoder.encode(BackupBundle(transactions: transactions, settings: settings))
    }

    var backupFileName: String { "Budget-sauvegarde-" + Self.backupDateFormatter.string(from: .now) + ".json" }

    @discardableResult
    func exportBackup(to url: URL) -> Bool {
        do {
            try backupFileData().write(to: url, options: .atomic)
            return true
        } catch {
            errorMessage = "L'export de la sauvegarde a échoué : \(error.localizedDescription)"
            return false
        }
    }

    /// Remplace toutes les données par celles du fichier (après l'avoir validé et sauvegardé l'état actuel).
    @discardableResult
    func importBackup(from url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bundle: BackupBundle
        do {
            bundle = try Self.decoder.decode(BackupBundle.self, from: Data(contentsOf: url))
        } catch {
            errorMessage = "Ce fichier n'est pas une sauvegarde Budget valide. Vos données n'ont pas été modifiées."
            return false
        }
        if hasData, createBackup(now: .now) == nil { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(bundle.transactions).write(to: transactionsURL, options: .atomic)
            try Self.encoder.encode(bundle.settings).write(to: settingsURL, options: .atomic)
        } catch {
            errorMessage = "L'import a échoué : \(error.localizedDescription)"
            reloadFromDisk()
            return false
        }
        reloadFromDisk()
        return true
    }

    static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        return formatter
    }()
}
