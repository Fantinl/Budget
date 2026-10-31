import { describe, expect, it } from "vitest";
import { makeStore, expense, tick } from "./test/support";
import { readText } from "./platform";
import { SyncKey } from "./sync/tracker";

describe("BudgetStore", () => {
  it("enregistre et relit les opérations", async () => {
    const s = await makeStore("/test/relire");
    s.upsert(expense(12.5, "groceries"));
    await s.flush();
    const again = await makeStore("/test/relire");
    expect(again.transactions.map(t => t.amountCents)).toEqual([1250]);
    expect(JSON.parse((await readText("/test/relire/transactions.json"))!)[0].amount).toBe(12.5);
  });

  it("annule et rétablit une action, regroupée sur une même tâche", async () => {
    const s = await makeStore();
    s.upsert(expense(1));
    s.upsert(expense(2));
    await tick();
    expect(s.transactions).toHaveLength(2);
    s.undo();
    expect(s.transactions).toHaveLength(0);
    s.redo();
    expect(s.transactions).toHaveLength(2);
  });

  it("horodate les modifications et les suppressions pour la synchro", async () => {
    const s = await makeStore();
    const t = expense(5);
    s.upsert(t);
    expect(s.sync.meta.modifiedAt[SyncKey.transaction + t.id]).toBeInstanceOf(Date);
    await tick();
    s.delete(t);
    expect(s.sync.meta.modifiedAt[SyncKey.transaction + t.id]).toBeUndefined();
    expect(s.sync.meta.deletedAt[SyncKey.transaction + t.id]).toBeInstanceOf(Date);
  });

  it("supprimer une catégorie réaffecte ses opérations à « Autre »", async () => {
    const s = await makeStore();
    s.upsert(expense(3, "restaurants"));
    await tick();
    s.deleteCategory(s.category("restaurants"));
    expect(s.transactions[0].categoryID).toBe("otherExpense");
    expect(s.categories.some(c => c.id === "restaurants")).toBe(false);
  });
});
