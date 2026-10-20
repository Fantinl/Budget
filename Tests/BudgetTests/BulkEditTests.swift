import XCTest
@testable import Budget

final class BulkEditTests: StoreTestCase {
    private func tagged(_ store: BudgetStore, _ name: String) -> Tag { store.addTag(named: name) }

    private func transaction(_ store: BudgetStore, _ id: UUID) -> Transaction { store.transactions.first { $0.id == id }! }

    func testAddTagToMixedSelectionAndPartialState() {
        let store = makeStore()
        let tag = tagged(store, "Vacances")
        var a = expense(3, on: day(2026, 10, 1)); a.tagIDs = [tag.id]
        let b = expense(4, on: day(2026, 10, 2))
        store.upsert(a); store.upsert(b)
        let ids: Set<UUID> = [a.id, b.id]
        XCTAssertEqual(store.tagState(tag, in: ids), .some)
        store.addTag(tag, to: ids)
        XCTAssertEqual(store.tagState(tag, in: ids), .all)
        XCTAssertEqual(transaction(store, a.id).tagIDs, [tag.id]) // pas de doublon
        XCTAssertEqual(makeStore().transactions.filter { $0.tagIDs == [tag.id] }.count, 2)
    }

    func testRemoveTag() {
        let store = makeStore()
        let tag = tagged(store, "Pro")
        var a = expense(3, on: day(2026, 10, 1)); a.tagIDs = [tag.id]
        var b = expense(4, on: day(2026, 10, 2)); b.tagIDs = [tag.id]
        store.upsert(a); store.upsert(b)
        store.removeTag(tag, from: [a.id, b.id])
        XCTAssertEqual(store.tagState(tag, in: [a.id, b.id]), .none)
        XCTAssertNil(transaction(store, a.id).tagIDs)
    }

    func testTagAppliesToBothTransferLegs() {
        let store = makeStore()
        let tag = tagged(store, "Épargne")
        let link = UUID()
        var out = expense(50, on: day(2026, 10, 1)); out.transferID = link
        var into = income(50, on: day(2026, 10, 1)); into.transferID = link
        store.upsert(out); store.upsert(into)
        store.addTag(tag, to: [out.id])
        XCTAssertEqual(transaction(store, into.id).tagIDs, [tag.id])
        XCTAssertEqual(store.tagState(tag, in: [out.id]), .all)
        store.removeTag(tag, from: [into.id])
        XCTAssertNil(transaction(store, out.id).tagIDs)
    }

    func testBulkEditChangesOnlyEditedFieldsAndKeepsDates() {
        let store = makeStore()
        let a = expense(3, "groceries", note: "A", on: day(2026, 10, 1))
        let b = expense(4, "restaurants", note: "B", on: day(2026, 10, 17))
        store.upsert(a); store.upsert(b)
        var edit = BulkEdit()
        edit.note = "Commun"
        XCTAssertEqual(store.applyBulkEdit(ids: [a.id, b.id], edit), 2)
        for original in [a, b] {
            let t = transaction(store, original.id)
            XCTAssertEqual(t.note, "Commun")
            XCTAssertEqual(t.amount, original.amount)
            XCTAssertEqual(t.categoryID, original.categoryID)
            XCTAssertEqual(t.date, original.date)
        }
    }

    func testSummaryMarksDifferingFieldsAsNil() {
        let a = expense(3, "groceries", note: "X", on: day(2026, 10, 1))
        let b = expense(3, "restaurants", note: "X", on: day(2026, 10, 3))
        let summary = BulkSummary([a, b])
        XCTAssertEqual(summary.amount, 3)
        XCTAssertNil(summary.categoryID)
        XCTAssertFalse(summary.isUniform)
        XCTAssertTrue(BulkSummary([a, expense(3, "groceries", note: "X", on: day(2026, 10, 9))]).isUniform)
    }

    func testBulkEditSetsAmountKindAndAccount() {
        let store = makeStore()
        let a = expense(3, "groceries", on: day(2026, 10, 1)), b = expense(3, "groceries", on: day(2026, 10, 2))
        store.upsert(a); store.upsert(b)
        store.applyBulkEdit(ids: [a.id, b.id], BulkEdit(amount: 12.5, kind: .income, accountID: "other"))
        let t = transaction(store, a.id)
        XCTAssertEqual(t.amount, 12.5)
        XCTAssertEqual(t.kind, .income)
        XCTAssertEqual(store.category(of: t).kind, .income) // catégorie alignée sur le type
        XCTAssertEqual(t.accountID, "other")
    }

    func testTransfersAreSkipped() {
        let store = makeStore()
        let link = UUID()
        var leg = expense(50, "otherExpense", note: "Virement", on: day(2026, 10, 1)); leg.transferID = link
        let a = expense(3, on: day(2026, 10, 2))
        store.upsert(leg); store.upsert(a)
        XCTAssertEqual(store.applyBulkEdit(ids: [leg.id, a.id], BulkEdit(amount: 9)), 1)
        XCTAssertEqual(transaction(store, leg.id).amount, 50)
        XCTAssertEqual(transaction(store, a.id).amount, 9)
    }

    func testUndoRevertsBulkEditInOneStep() {
        let store = makeStore()
        let a = expense(3, on: day(2026, 10, 1)), b = expense(4, on: day(2026, 10, 2))
        store.upsert(a); store.upsert(b)
        let tag = tagged(store, "T")
        let manager = attachUndoManager(to: store)
        inUndoGroup(manager) {
            store.applyBulkEdit(ids: [a.id, b.id], BulkEdit(amount: 7, note: "N", addTagIDs: [tag.id]))
        }
        manager.undo()
        XCTAssertEqual(transaction(store, a.id).amount, 3)
        XCTAssertEqual(transaction(store, b.id).amount, 4)
        XCTAssertNil(transaction(store, a.id).tagIDs)
        inUndoGroup(manager) { store.addTag(tag, to: [a.id, b.id]) }
        manager.undo()
        XCTAssertEqual(store.tagState(tag, in: [a.id, b.id]), .none)
    }
}
