// Port des tests de réordonnancement (ReorderTests), catégories (CategoryTests) et annulation (UndoTests) liés aux réglages.
import { describe, expect, it } from "vitest";
import { day, expense, income, makeStore, tick } from "../../lib/test/support";
import { defaultCategories, newID, type Category, type QuickExpense } from "../../lib/model";
import { moveDestination } from "./settingsLogic";
import { moveItems } from "../../lib/logic/accounts";
const moveItem = <T,>(items: readonly T[], from: number, to: number) => moveItems(items, [from], to);

const quick = (name: string): QuickExpense => ({ id: newID(), name, amountCents: 100, kind: "expense", categoryID: "otherExpense", note: "", accountID: null });

describe("Réordonnancement", () => {
  it("calcule les destinations", () => {
    expect(moveDestination("up", 1, 3)).toBe(0);
    expect(moveDestination("up", 0, 3)).toBe(0);
    expect(moveDestination("down", 0, 3)).toBe(2);
    expect(moveDestination("down", 2, 3)).toBe(3);
    expect(moveDestination("first", 2, 3)).toBe(0);
    expect(moveDestination("last", 0, 3)).toBe(3);
  });

  it("réordonne les ajouts rapides", async () => {
    const s = await makeStore();
    s.quickExpenses = [];
    for (const n of ["A", "B", "C"]) s.upsertQuickExpense(quick(n));
    const names = () => s.quickExpenses.map(q => q.name).join("");
    const move = (from: number, m: Parameters<typeof moveDestination>[0]) =>
      s.reorderQuickExpenses(moveItem(s.quickExpenses, from, moveDestination(m, from, 3)).map(q => q.id));
    move(1, "up"); expect(names()).toBe("BAC");
    move(0, "down"); expect(names()).toBe("ABC");
    move(0, "last"); expect(names()).toBe("BCA");
    move(2, "first"); expect(names()).toBe("ABC");
    await s.flush();
    expect((await makeStore(s.directory)).quickExpenses.map(q => q.name).join("")).toBe("ABC");
  });

  it("réordonne les catégories sans sortir de leur type", async () => {
    const s = await makeStore();
    for (const n of ["X", "Y", "Z"]) s.upsertCategory({ ...defaultCategories[0], id: newID(), label: n } as Category);
    const expenses = s.categoriesFor("expense");
    const incomeBefore = s.categoriesFor("income").map(c => c.id);
    const last = expenses.length - 1;
    s.reorderCategories("expense", moveItem(expenses, last, moveDestination("first", last, expenses.length)).map(c => c.id));
    expect(s.categoriesFor("expense")[0].id).toBe(expenses[last].id);
    expect(s.categoriesFor("expense")).toHaveLength(expenses.length);
    expect(s.categoriesFor("income").map(c => c.id)).toEqual(incomeBefore);
  });
});

describe("Catégories (réglages)", () => {
  it("supprimer une catégorie utilisée déplace tout dans Autre", async () => {
    const s = await makeStore();
    s.upsert(expense(10, "groceries", day(2026, 10, 1)));
    s.recurringOperations = [{ id: newID(), name: "Loyer", amountCents: 70000, kind: "expense", categoryID: "groceries", accountID: null,
      note: "", frequency: "monthly", startDate: day(2026, 1, 1), endDate: null, isActive: true, lastGeneratedDate: null }];
    s.upsertQuickExpense({ ...quick("Pain"), categoryID: "groceries" });
    s.deleteCategory(s.category("groceries"));
    expect(s.transactions.some(t => t.categoryID === "groceries")).toBe(false);
    expect(s.recurringOperations.some(r => r.categoryID === "groceries")).toBe(false);
    expect(s.quickExpenses.some(q => q.categoryID === "groceries")).toBe(false);
    expect(s.transactions[0].categoryID).toBe("otherExpense");
    expect(s.categories.some(c => c.id === "groceries")).toBe(false);
  });

  it("les catégories Autre ne se suppriment pas", async () => {
    const s = await makeStore();
    const other = s.category("otherExpense");
    expect(s.isProtected(other)).toBe(true);
    s.deleteCategory(other);
    expect(s.categories.some(c => c.id === "otherExpense")).toBe(true);
  });

  it("un revenu retombe sur Autre revenu", async () => {
    const s = await makeStore();
    s.upsert(income(100, day(2026, 10, 1), "salary"));
    s.deleteCategory(s.category("salary"));
    expect(s.transactions[0].categoryID).toBe("otherIncome");
  });

  it("catégorie inconnue, usage et masquage", async () => {
    const s = await makeStore();
    expect(s.category("nope").label).toBe("Sans catégorie");
    s.upsert(expense(1, "leisure", day(2026, 10, 1)));
    await tick();
    const leisure = s.category("leisure");
    expect(s.usageCount(leisure)).toBe(1);
    expect(s.isUsed(leisure)).toBe(true);
    s.upsertCategory({ ...leisure, isHidden: true });
    expect(s.categoriesFor("expense").some(c => c.id === "leisure")).toBe(false);
    expect(s.categoriesFor("expense", true).some(c => c.id === "leisure")).toBe(true);
  });

  it("la suppression est enregistrée et annulable", async () => {
    const s = await makeStore();
    s.deleteCategory(s.category("health"));
    await s.flush();
    expect((await makeStore(s.directory)).categories.some(c => c.id === "health")).toBe(false);
    s.undo();
    await s.flush();
    expect(s.categories.some(c => c.id === "health")).toBe(true);
    expect((await makeStore(s.directory)).categories.some(c => c.id === "health")).toBe(true);
  });
});

