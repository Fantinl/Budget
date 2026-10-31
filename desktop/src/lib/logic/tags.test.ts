import { describe, expect, it } from "vitest";
import { makeStore, day, expense, tick } from "../test/support";
import { emptyFilter, isFilterActive, matches } from "./filter";
import { addTag, deleteTag, moveTags, tagUsageCount, tagsOf } from "./tags";

describe("Tags", () => {
  it("addTag évite les doublons", async () => {
    const s = await makeStore();
    const a = addTag(s, "Vacances"), b = addTag(s, "  #vacances ");
    const c = addTag(s, "Café"), d = addTag(s, "cafe");
    expect(a.id).toBe(b.id);
    expect(c.id).toBe(d.id);
    expect(s.tags).toHaveLength(2);
    expect(a.name).toBe("Vacances");
  });

  it("supprimer un tag le retire des opérations", async () => {
    const s = await makeStore();
    const keep = addTag(s, "a"), gone = addTag(s, "b");
    const t1 = { ...expense(10, "otherExpense", day(2026, 1, 1)), tagIDs: [gone.id] };
    const t2 = { ...expense(5, "otherExpense", day(2026, 1, 2)), tagIDs: [keep.id, gone.id] };
    s.upsert(t1); s.upsert(t2);
    await tick();
    expect(tagUsageCount(s, gone)).toBe(2);
    deleteTag(s, gone);
    expect(s.transactions).toHaveLength(2);
    expect(s.transactions.find(t => t.id === t1.id)?.tagIDs).toBeNull();
    expect(s.transactions.find(t => t.id === t2.id)?.tagIDs).toEqual([keep.id]);
    expect(s.tags.map(t => t.id)).toEqual([keep.id]);
  });

  it("les tags d'une opération suivent l'ordre du magasin et ignorent l'inconnu", async () => {
    const s = await makeStore();
    const a = addTag(s, "a"), b = addTag(s, "b");
    const t = { ...expense(1, "otherExpense", day(2026, 1, 1)), tagIDs: [b.id, "inconnu", a.id] };
    expect(tagsOf(s, t).map(x => x.id)).toEqual([a.id, b.id]);
  });

  it("réordonne", async () => {
    const s = await makeStore();
    const a = addTag(s, "a"), b = addTag(s, "b"), c = addTag(s, "c");
    moveTags(s, [2], 0);
    expect(s.tags.map(t => t.id)).toEqual([c.id, a.id, b.id]);
    await tick();
    moveTags(s, [0], 3);
    expect(s.tags.map(t => t.id)).toEqual([a.id, b.id, c.id]);
  });

  it("filtre par tag", async () => {
    const s = await makeStore();
    const a = addTag(s, "a"), b = addTag(s, "b");
    const t1 = { ...expense(1), tagIDs: [a.id] }, t2 = { ...expense(1), tagIDs: [b.id] }, t3 = expense(1);
    const filter = emptyFilter();
    expect(isFilterActive(filter)).toBe(false);
    filter.tagIDs = [a.id, b.id];
    expect(isFilterActive(filter)).toBe(true);
    expect(matches(filter, t1)).toBe(true);
    expect(matches(filter, t2)).toBe(true);
    expect(matches(filter, t3)).toBe(false);
    filter.tagIDs = [a.id];
    expect(matches(filter, t2)).toBe(false);
  });

  it("persiste", async () => {
    const s = await makeStore();
    const tag = addTag(s, "Cadeau");
    s.upsert({ ...expense(12, "otherExpense", day(2026, 2, 1)), tagIDs: [tag.id] });
    await s.flush();
    const again = await makeStore(s.directory);
    expect(again.tags).toEqual([tag]);
    expect(again.transactions[0].tagIDs).toEqual([tag.id]);
  });

  it("annule la suppression d'un tag", async () => {
    const s = await makeStore();
    const tag = addTag(s, "x");
    await tick();
    s.upsert({ ...expense(3, "otherExpense", day(2026, 3, 1)), tagIDs: [tag.id] });
    await tick();
    deleteTag(s, tag);
    expect(s.tags).toHaveLength(0);
    s.undo();
    expect(s.tags).toEqual([tag]);
    expect(s.transactions[0].tagIDs).toEqual([tag.id]);
  });
});
