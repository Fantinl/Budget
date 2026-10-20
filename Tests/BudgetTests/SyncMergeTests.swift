import XCTest
@testable import Budget

final class SyncMergeTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    func snapshot(_ device: String, transactions: [(Transaction, TimeInterval)] = [],
                  deleted: [(Transaction, TimeInterval)] = [], categories: [Budget.Category] = [],
                  at when: TimeInterval = 0) -> SyncSnapshot {
        var s = SyncSnapshot(deviceID: device, date: at(when))
        s.categories = categories
        for (t, stamp) in transactions {
            s.transactions.append(t)
            s.modifiedAt[SyncKey.transaction + t.id.uuidString] = at(stamp)
        }
        for (t, stamp) in deleted { s.deletedAt[SyncKey.transaction + t.id.uuidString] = at(stamp) }
        return s
    }

    func tx(_ note: String) -> Transaction { expense(10, note: note, on: day(2026, 10, 1)) }

    func merge(_ a: SyncSnapshot, _ b: SyncSnapshot) -> SyncSnapshot { SyncMerge.merge(local: a, remote: b, now: base) }

    func testAddedOnBothSidesIsUnion() {
        let a = tx("A"), b = tx("B")
        let m = merge(snapshot("A", transactions: [(a, 1)]), snapshot("B", transactions: [(b, 2)]))
        XCTAssertEqual(Set(m.transactions.map(\.note)), ["A", "B"])
    }

    func testConcurrentEditMostRecentWins() {
        var t = tx("origine")
        var older = t; older.note = "ancien"
        var newer = t; newer.note = "récent"
        t.note = "x"
        let m1 = merge(snapshot("A", transactions: [(older, 5)]), snapshot("B", transactions: [(newer, 9)]))
        let m2 = merge(snapshot("B", transactions: [(newer, 9)]), snapshot("A", transactions: [(older, 5)]))
        XCTAssertEqual(m1.transactions.first?.note, "récent")
        XCTAssertEqual(m2.transactions.first?.note, "récent")
        XCTAssertEqual(m1.transactions.count, 1)
    }

    func testDeletionNewerThanEditWins() {
        let t = tx("à supprimer")
        let m = merge(snapshot("A", transactions: [(t, 5)]), snapshot("B", deleted: [(t, 8)]))
        XCTAssertTrue(m.transactions.isEmpty)
        XCTAssertNotNil(m.deletedAt[SyncKey.transaction + t.id.uuidString])
        XCTAssertNil(m.modifiedAt[SyncKey.transaction + t.id.uuidString])
    }

    func testEditNewerThanDeletionWins() {
        let t = tx("sauvée")
        let m = merge(snapshot("A", transactions: [(t, 9)]), snapshot("B", deleted: [(t, 8)]))
        XCTAssertEqual(m.transactions.count, 1)
        XCTAssertTrue(m.deletedAt.isEmpty)
    }

    func testIdempotenceAndCommutativity() {
        var shared = tx("commun")
        let onlyA = tx("a"), onlyB = tx("b"), gone = tx("gone")
        var edited = shared; edited.note = "modifié"
        shared.note = "commun"
        let a = snapshot("A", transactions: [(shared, 1), (onlyA, 2), (gone, 3)], at: 10)
        let b = snapshot("B", transactions: [(edited, 4), (onlyB, 2)], deleted: [(gone, 5)], at: 11)
        let m = merge(a, b)
        XCTAssertEqual(merge(a, m), m)
        XCTAssertEqual(merge(m, a), m)
        XCTAssertEqual(merge(m, m), m)
        XCTAssertTrue(merge(b, a).sameContent(as: m))
        XCTAssertEqual(m.transactions.count, 3)
    }

    func testExactTieIsSymmetricAndIdempotent() {
        let t = tx("x")
        var other = t; other.note = "y"
        let a = snapshot("A", transactions: [(t, 5)])
        let b = snapshot("B", transactions: [(other, 5)])
        let m = merge(a, b)
        XCTAssertTrue(merge(b, a).sameContent(as: m))
        XCTAssertEqual(merge(a, m), m)
        XCTAssertEqual(merge(b, m), merge(m, b))
    }

    func testListOrderFollowsMostRecentOrderThenAppendsUnknown() {
        let c1 = Budget.Category(id: "1", label: "1", icon: "x", kind: .expense, colorIndex: 0)
        let c2 = Budget.Category(id: "2", label: "2", icon: "x", kind: .expense, colorIndex: 0)
        let c3 = Budget.Category(id: "3", label: "3", icon: "x", kind: .expense, colorIndex: 0)
        let c4 = Budget.Category(id: "4", label: "4", icon: "x", kind: .expense, colorIndex: 0)
        var a = snapshot("A", categories: [c1, c2, c3])
        var b = snapshot("B", categories: [c3, c2, c1, c4])
        a.settingsAt[SyncKey.orderCategories] = at(5)
        b.settingsAt[SyncKey.orderCategories] = at(9)
        let m = merge(a, b)
        XCTAssertEqual(m.categories.map(\.id), ["3", "2", "1", "4"])
        // L'ordre de A est plus récent : « 4 », inconnu de A, arrive à la fin.
        a.settingsAt[SyncKey.orderCategories] = at(20)
        XCTAssertEqual(merge(a, b).categories.map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(merge(b, a).categories.map(\.id), ["1", "2", "3", "4"])
    }

    func testDefaultAccountMostRecentWins() {
        var a = snapshot("A"), b = snapshot("B")
        a.defaultAccountID = "livret"; a.settingsAt[SyncKey.defaultAccount] = at(9)
        b.defaultAccountID = "main"; b.settingsAt[SyncKey.defaultAccount] = at(3)
        XCTAssertEqual(merge(a, b).defaultAccountID, "livret")
        XCTAssertEqual(merge(b, a).defaultAccountID, "livret")
    }

    func testOldTombstonesArePurged() {
        let old = tx("vieux"), recent = tx("récent")
        let day90: TimeInterval = 90 * 24 * 3600
        let a = snapshot("A", deleted: [(old, -day90 - 100), (recent, -day90 + 3600)])
        let m = merge(a, snapshot("B"))
        XCTAssertNil(m.deletedAt[SyncKey.transaction + old.id.uuidString])
        XCTAssertNotNil(m.deletedAt[SyncKey.transaction + recent.id.uuidString])
    }
}
