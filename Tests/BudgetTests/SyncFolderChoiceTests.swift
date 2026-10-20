import XCTest
@testable import Budget

/// Le dossier de synchro doit être partagé : le dossier privé de l'app est refusé.
@MainActor
final class SyncFolderChoiceTests: XCTestCase {
    func testOwnDataFolderIsRejected() {
        XCTAssertTrue(SyncCoordinator.isAppPrivateFolder(BudgetStore.defaultDirectory))
        XCTAssertTrue(SyncCoordinator.isAppPrivateFolder(BudgetStore.defaultDirectory.appending(path: "Sync")))
    }

    func testSharedFolderIsAccepted() {
        let iCloud = URL.homeDirectory.appending(path: "Library/Mobile Documents/com~apple~CloudDocs/Budget")
        XCTAssertFalse(SyncCoordinator.isAppPrivateFolder(iCloud))
        XCTAssertFalse(SyncCoordinator.isAppPrivateFolder(FileManager.default.temporaryDirectory))
    }
}
