import { describe, expect, it } from "vitest";
import { makeStore, day, expense, income, tick } from "../test/support";
import { newID } from "../model";
import { addTag } from "./tags";
import {
  addTagTo, applyBulkEdit, bulkSummary, deleteTransactions, duplicateTransactions, emptyBulkEdit, isUniform, removeTagFrom,
  tagState, updateTransactions,
} from "./bulk";

const ex = (euros: number, note: string, date: Date, cat = "otherExpense") => ({ ...expense(euros, cat, date), note });
const edit = (fields: object) => ({ ...emptyBulkEdit(), ...fields });

describe("Actions groupées", () => {
  it("recatégorise", async () => {
    const s = await makeStore();
    const a = ex(3, "A", day(2026, 10, 1)), b = ex(4, "B", day(2026, 10, 2)), c = ex(5, "C", day(2026, 10, 3));
    for (const t of [a, b, c]) s.upsert(t);
    await tick();
    expect(updateTransactions(s, new Set([a.id, b.id]), t => ({ ...t, categoryID: "restaurants" }))).toBe(2);
    expect(s.transactions.filter(t => t.categoryID === "restaurants")).toHaveLength(2);
    expect(s.transactions.find(t => t.id === c.id)?.categoryID).toBe("otherExpense");
    await s.flush();
    expect((await makeStore(s.directory)).transactions.filter(t => t.categoryID === "restaurants")).toHaveLength(2);
  });

  it("des identifiants inconnus ne font rien", async () => {
    const s = await makeStore();
    expect(updateTransactions(s, new Set([newID()]), t => ({ ...t, amountCents: 100 }))).toBe(0);
  });

  it("supprime en lot", async () => {
    const s = await makeStore();
    const a = ex(3, "", day(2026, 10, 1)), b = ex(4, "", day(2026, 10, 2));
    s.upsert(a); s.upsert(b);
    await tick();
    expect(deleteTransactions(s, new Set([a.id]))).toBe(1);
    expect(s.transactions.map(t => t.id)).toEqual([b.id]);
    expect(deleteTransactions(s, new Set([newID()]))).toBe(0);
  });

  it("la copie garde les champs et la date mais pas le lien récurrent", async () => {
    const s = await makeStore();
    const source = { ...ex(3, "Pain", day(2020, 1, 1), "groceries"), recurringID: newID() };
    s.upsert(source);
    await tick();
    const copies = duplicateTransactions(s, new Set([source.id]));
    expect(copies).toHaveLength(1);
    expect(copies[0].id).not.toBe(source.id);
    expect(copies[0].amountCents).toBe(300);
    expect(copies[0].note).toBe("Pain");
    expect(copies[0].recurringID).toBeNull();
    expect(copies[0].date.getTime()).toBe(source.date.getTime());
    expect(s.transactions).toHaveLength(2);
  });
});

describe("Modification groupée", () => {
  it("ajoute un tag à une sélection mixte", async () => {
    const s = await makeStore();
    const tag = addTag(s, "Vacances");
    const a = { ...ex(3, "", day(2026, 10, 1)), tagIDs: [tag.id] };
    const b = ex(4, "", day(2026, 10, 2));
    s.upsert(a); s.upsert(b);
    await tick();
    const ids = new Set([a.id, b.id]);
    expect(tagState(s, tag.id, ids)).toBe("some");
    addTagTo(s, tag.id, ids);
    expect(tagState(s, tag.id, ids)).toBe("all");
    expect(s.transactions.find(t => t.id === a.id)?.tagIDs).toEqual([tag.id]); // pas de doublon
  });

  it("retire un tag", async () => {
    const s = await makeStore();
    const tag = addTag(s, "Pro");
    const a = { ...ex(3, "", day(2026, 10, 1)), tagIDs: [tag.id] }, b = { ...ex(4, "", day(2026, 10, 2)), tagIDs: [tag.id] };
    s.upsert(a); s.upsert(b);
    await tick();
    removeTagFrom(s, tag.id, new Set([a.id, b.id]));
    expect(tagState(s, tag.id, new Set([a.id, b.id]))).toBe("none");
    expect(s.transactions.find(t => t.id === a.id)?.tagIDs).toBeNull();
  });

  it("le tag vaut pour les deux jambes d'un virement", async () => {
    const s = await makeStore();
    const tag = addTag(s, "Épargne");
    const link = newID();
    const out = { ...ex(50, "", day(2026, 10, 1)), transferID: link };
    const into = { ...income(50, day(2026, 10, 1), "otherIncome"), transferID: link };
    s.upsert(out); s.upsert(into);
    await tick();
    addTagTo(s, tag.id, new Set([out.id]));
    expect(s.transactions.find(t => t.id === into.id)?.tagIDs).toEqual([tag.id]);
    expect(tagState(s, tag.id, new Set([out.id]))).toBe("all");
    removeTagFrom(s, tag.id, new Set([into.id]));
    expect(s.transactions.find(t => t.id === out.id)?.tagIDs).toBeNull();
  });

  it("ne change que les champs édités et garde les dates", async () => {
    const s = await makeStore();
    const a = ex(3, "A", day(2026, 10, 1), "groceries"), b = ex(4, "B", day(2026, 10, 17), "restaurants");
    s.upsert(a); s.upsert(b);
    await tick();
    expect(applyBulkEdit(s, new Set([a.id, b.id]), edit({ note: "Commun" }))).toBe(2);
    for (const original of [a, b]) {
      const t = s.transactions.find(x => x.id === original.id)!;
      expect(t.note).toBe("Commun");
      expect(t.amountCents).toBe(original.amountCents);
      expect(t.categoryID).toBe(original.categoryID);
      expect(t.date.getTime()).toBe(original.date.getTime());
    }
  });

  it("résume les champs communs", () => {
    const a = ex(3, "X", day(2026, 10, 1), "groceries"), b = ex(3, "X", day(2026, 10, 3), "restaurants");
    const summary = bulkSummary([a, b]);
    expect(summary.amountCents).toBe(300);
    expect(summary.categoryID).toBeNull();
    expect(isUniform(summary)).toBe(false);
    expect(isUniform(bulkSummary([a, ex(3, "X", day(2026, 10, 9), "groceries")]))).toBe(true);
    expect(summary.firstDate?.getTime()).toBe(a.date.getTime());
    expect(summary.lastDate?.getTime()).toBe(b.date.getTime());
  });

  it("change montant, type et compte", async () => {
    const s = await makeStore();
    const a = ex(3, "", day(2026, 10, 1), "groceries"), b = ex(3, "", day(2026, 10, 2), "groceries");
    s.upsert(a); s.upsert(b);
    await tick();
    applyBulkEdit(s, new Set([a.id, b.id]), edit({ amountCents: 1250, kind: "income", accountID: "other" }));
    const t = s.transactions.find(x => x.id === a.id)!;
    expect(t.amountCents).toBe(1250);
    expect(t.kind).toBe("income");
    expect(s.categoryOf(t).kind).toBe("income"); // catégorie alignée sur le type
    expect(t.accountID).toBe("other");
  });

  it("ignore les virements", async () => {
    const s = await makeStore();
    const leg = { ...ex(50, "Virement", day(2026, 10, 1)), transferID: newID() };
    const a = ex(3, "", day(2026, 10, 2));
    s.upsert(leg); s.upsert(a);
    await tick();
    expect(applyBulkEdit(s, new Set([leg.id, a.id]), edit({ amountCents: 900 }))).toBe(1);
    expect(s.transactions.find(t => t.id === leg.id)?.amountCents).toBe(5000);
    expect(s.transactions.find(t => t.id === a.id)?.amountCents).toBe(900);
  });

  it("une annulation défait toute la modification", async () => {
    const s = await makeStore();
    const a = ex(3, "", day(2026, 10, 1)), b = ex(4, "", day(2026, 10, 2));
    s.upsert(a); s.upsert(b);
    await tick();
    const tag = addTag(s, "T");
    await tick();
    applyBulkEdit(s, new Set([a.id, b.id]), edit({ amountCents: 700, note: "N", addTagIDs: [tag.id] }));
    expect(s.undoActionName).toBe("Modifier 2 opérations");
    await tick();
    s.undo();
    expect(s.transactions.find(t => t.id === a.id)?.amountCents).toBe(300);
    expect(s.transactions.find(t => t.id === b.id)?.amountCents).toBe(400);
    expect(s.transactions.find(t => t.id === a.id)?.tagIDs).toBeNull();
    addTagTo(s, tag.id, new Set([a.id, b.id]));
    await tick();
    s.undo();
    expect(tagState(s, tag.id, new Set([a.id, b.id]))).toBe("none");
  });
});
