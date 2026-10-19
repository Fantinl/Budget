import XCTest
@testable import Budget

/// Base des tests qui touchent au disque : chaque test a son propre dossier temporaire,
/// supprimé à la fin. Jamais de lecture ni d'écriture dans ~/Library/Application Support/Budget.
@MainActor
class StoreTestCase: XCTestCase {
    var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appending(path: "BudgetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
        super.tearDown()
    }

    func makeStore() -> BudgetStore { BudgetStore(directory: dir) }

    /// Écrit un fichier texte dans le dossier du test.
    func write(_ text: String, as name: String) throws {
        try text.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
    }

    /// Gestionnaire d'annulation sans regroupement automatique (pas de boucle d'événements en test).
    func attachUndoManager(to store: BudgetStore) -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        store.undoManager = manager
        return manager
    }

    /// Exécute `action` dans un groupe d'annulation.
    func inUndoGroup(_ manager: UndoManager, _ action: () -> Void) {
        manager.beginUndoGrouping()
        action()
        manager.endUndoGrouping()
    }
}

/// Date à midi (calendrier courant), pour éviter les effets de fuseau.
func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 12) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour))!
}

/// Début de journée (les échéances récurrentes tombent à 00:00).
func startOfDay(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

func expense(_ amount: Decimal, _ category: String = "otherExpense", note: String = "", on date: Date, account: String? = nil) -> Transaction {
    Transaction(amount: amount, kind: .expense, categoryID: category, note: note, date: date, accountID: account)
}

func income(_ amount: Decimal, _ category: String = "otherIncome", note: String = "", on date: Date, account: String? = nil) -> Transaction {
    Transaction(amount: amount, kind: .income, categoryID: category, note: note, date: date, accountID: account)
}
