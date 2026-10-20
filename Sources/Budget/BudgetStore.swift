import Foundation
import Observation

/// Garde les données en mémoire et les enregistre dans deux fichiers JSON
/// (~/Library/Application Support/Budget/ sur Mac) :
/// - transactions.json : les opérations ;
/// - settings.json : catégories, dépenses rapides, comptes et opérations récurrentes.
///
/// Les fonctionnalités sont réparties en extensions (BudgetStore+Recurring, +Backup, +Accounts…).
/// Elles modifient directement les tableaux ci-dessous puis appellent `saveTransactions()` /
/// `saveSettings()`.
@MainActor
@Observable
final class BudgetStore {
    var transactions: [Transaction] = []
    var categories: [Category] = Category.defaults
    var quickExpenses: [QuickExpense] = QuickExpense.defaults
    var accounts: [Account] = [.main]
    var recurringOperations: [RecurringOperation] = []
    var tags: [Tag] = []
    /// Compte proposé par défaut pour les nouvelles opérations (réglages). Voir `defaultAccount`.
    var defaultAccountID: String = Account.mainID
    var errorMessage: String?
    /// Gestionnaire d'annulation de la fenêtre active (voir BudgetStore+Undo.swift).
    @ObservationIgnored weak var undoManager: UndoManager?

    let directory: URL
    var transactionsURL: URL { directory.appending(path: "transactions.json") }
    var settingsURL: URL { directory.appending(path: "settings.json") }

    init(directory: URL = BudgetStore.defaultDirectory) {
        self.directory = directory
        reloadFromDisk()
    }

    /// (Re)lit les fichiers. Utilisé au lancement et après une restauration de sauvegarde.
    func reloadFromDisk() {
        transactions = load(transactionsURL) ?? []
        let settings: Settings = load(settingsURL) ?? Settings()
        categories = settings.categories
        quickExpenses = settings.quickExpenses
        accounts = settings.accounts
        recurringOperations = settings.recurringOperations
        tags = settings.tags
        defaultAccountID = settings.defaultAccountID
        // Comptes Izly créés avant le décompte automatique : un repas par jour (lun→ven) à partir d'aujourd'hui.
        for index in accounts.indices where accounts[index].kind == .izly && accounts[index].mealPlan == nil {
            accounts[index].mealPlan = MealPlan()
        }
        if !accounts.contains(where: { $0.id == Account.mainID }) {
            accounts.insert(.main, at: 0)
        }
        // Les catégories « Autre » reçoivent les opérations des catégories supprimées : elles doivent exister.
        for kind in TransactionKind.allCases where !categories.contains(where: { $0.id == Self.fallbackID(for: kind) }) {
            if let fallback = Category.defaults.first(where: { $0.id == Self.fallbackID(for: kind) }) {
                categories.append(fallback)
            }
        }
    }

    nonisolated static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Budget", directoryHint: .isDirectory)
    }

    // MARK: - Opérations

    func upsert(_ transaction: Transaction) {

        registerUndo("Modifier l’opération")
        if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
            transactions[index] = transaction
        } else {
            transactions.append(transaction)
        }
        saveTransactions()
    }

    func delete(_ transaction: Transaction) {

        registerUndo("Supprimer l’opération")
        transactions.removeAll { $0.id == transaction.id }
        saveTransactions()
    }

    func transactions(inMonthOf month: Date) -> [Transaction] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return transactions
            .filter { interval.contains($0.date) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Catégories

    /// Catégorie d'un identifiant ; une catégorie supprimée renvoie « Sans catégorie ».
    func category(id: String) -> Category {
        categories.first { $0.id == id } ?? .unknown(id: id)
    }

    func category(of transaction: Transaction) -> Category {
        category(id: transaction.categoryID)
    }

    /// Catégories proposées pour un type d'opération, dans l'ordre choisi par l'utilisateur.
    func categories(for kind: TransactionKind, includeHidden: Bool = false) -> [Category] {
        categories.filter { $0.kind == kind && (includeHidden || !$0.isHidden) }
    }

    func isUsed(_ category: Category) -> Bool {
        usageCount(of: category) > 0
            || quickExpenses.contains { $0.categoryID == category.id }
            || recurringOperations.contains { $0.categoryID == category.id }
    }

    /// Nombre d'opérations rangées dans cette catégorie.
    func usageCount(of category: Category) -> Int {
        transactions.reduce(0) { $0 + ($1.categoryID == category.id ? 1 : 0) }
    }

    /// Identifiant de la catégorie « Autre » d'un type, qui récupère les opérations des catégories supprimées.
    nonisolated static func fallbackID(for kind: TransactionKind) -> String {
        kind == .expense ? "otherExpense" : "otherIncome"
    }

    func fallbackCategory(for kind: TransactionKind) -> Category {
        category(id: Self.fallbackID(for: kind))
    }

    /// Les catégories « Autre » ne peuvent pas être supprimées.
    func isProtected(_ category: Category) -> Bool {
        category.id == Self.fallbackID(for: category.kind)
    }

    func upsertCategory(_ category: Category) {

        registerUndo("Modifier la catégorie")
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        saveSettings()
    }

    /// Supprime une catégorie. Ses opérations et dépenses rapides sont réaffectées à « Autre »
    /// (l'interface doit avoir demandé confirmation si la catégorie était utilisée).
    func deleteCategory(_ category: Category) {
        registerUndo("Supprimer la catégorie")
        guard !isProtected(category) else { return }
        let fallbackID = Self.fallbackID(for: category.kind)
        if transactions.contains(where: { $0.categoryID == category.id }) {
            for index in transactions.indices where transactions[index].categoryID == category.id {
                transactions[index].categoryID = fallbackID
            }
            saveTransactions()
        }
        for index in quickExpenses.indices where quickExpenses[index].categoryID == category.id {
            quickExpenses[index].categoryID = fallbackID
        }
        for index in recurringOperations.indices where recurringOperations[index].categoryID == category.id {
            recurringOperations[index].categoryID = fallbackID
        }
        categories.removeAll { $0.id == category.id }
        saveSettings()
    }

    /// Réordonne les catégories d'un type (indices relatifs à `categories(for:includeHidden: true)`).
    func moveCategories(of kind: TransactionKind, from source: IndexSet, to destination: Int) {
        registerUndo("Réordonner les catégories")
        var subset = categories(for: kind, includeHidden: true)
        subset.move(fromOffsets: source, toOffset: destination)
        categories = categories.filter { $0.kind != kind } + subset
        saveSettings()
    }

    // MARK: - Dépenses rapides

    func upsertQuickExpense(_ quick: QuickExpense) {

        registerUndo("Modifier l’ajout rapide")
        if let index = quickExpenses.firstIndex(where: { $0.id == quick.id }) {
            quickExpenses[index] = quick
        } else {
            quickExpenses.append(quick)
        }
        saveSettings()
    }

    func deleteQuickExpense(_ quick: QuickExpense) {

        registerUndo("Supprimer l’ajout rapide")
        quickExpenses.removeAll { $0.id == quick.id }
        saveSettings()
    }

    func moveQuickExpenses(from source: IndexSet, to destination: Int) {

        registerUndo("Réordonner les ajouts rapides")
        quickExpenses.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }

    /// Enregistre une dépense rapide comme opération et la renvoie (utile pour annuler).
    @discardableResult
    func add(_ quick: QuickExpense, date: Date = .now) -> Transaction {
        let transaction = makeTransaction(from: quick, date: date)
        upsert(transaction)
        return transaction
    }

    // MARK: - Persistance

    struct Settings: Codable {
        var categories = Category.defaults
        var quickExpenses = QuickExpense.defaults
        var accounts = [Account.main]
        var recurringOperations: [RecurringOperation] = []
        var defaultAccountID = Account.mainID
        var tags: [Tag] = []

        init() {}

        init(categories: [Category], quickExpenses: [QuickExpense], accounts: [Account],
             recurringOperations: [RecurringOperation], defaultAccountID: String, tags: [Tag]) {
            self.tags = tags
            self.categories = categories
            self.quickExpenses = quickExpenses
            self.accounts = accounts
            self.recurringOperations = recurringOperations
            self.defaultAccountID = defaultAccountID
        }

        // Clés absentes (fichiers d'une version précédente) → valeurs par défaut.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? Category.defaults
            quickExpenses = try c.decodeIfPresent([QuickExpense].self, forKey: .quickExpenses) ?? QuickExpense.defaults
            accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? [.main]
            recurringOperations = try c.decodeIfPresent([RecurringOperation].self, forKey: .recurringOperations) ?? []
            defaultAccountID = try c.decodeIfPresent(String.self, forKey: .defaultAccountID) ?? Account.mainID
            tags = try c.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        }
    }

    func saveTransactions() {
        save(transactions, to: transactionsURL)
    }

    func saveSettings() {
        save(Settings(categories: categories, quickExpenses: quickExpenses, accounts: accounts,
                      recurringOperations: recurringOperations, defaultAccountID: defaultAccountID, tags: tags), to: settingsURL)
    }

    func load<T: Decodable>(_ url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Self.decoder.decode(T.self, from: Data(contentsOf: url))
        } catch {
            // On met le fichier illisible de côté plutôt que de l'écraser à la prochaine sauvegarde.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("illisible-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            errorMessage = "Le fichier \(url.lastPathComponent) n'a pas pu être lu. Une copie a été gardée : \(backup.lastPathComponent)"
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            errorMessage = "Échec de l'enregistrement : \(error.localizedDescription)"
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
