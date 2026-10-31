import { describe, expect, it } from "vitest";
import { makeStore, day, expense, income, op } from "../test/support";
import { newAccount, newID } from "../model";
import { emptyFilter, foldText, isFilterActive, isHiddenFromOperations, izlySpending, matches, matchesSearch, toggled } from "./filter";
import { addTag } from "./tags";

describe("Filtres des opérations", () => {
  it("filtre par type", () => {
    const transfer = op(10, { transferID: newID() });
    const f = { ...emptyFilter(), kind: "expense" as const };
    expect(matches(f, expense(3))).toBe(true);
    expect(matches(f, income(3))).toBe(false);
    expect(matches(f, transfer)).toBe(false);
    expect(matches({ ...f, kind: "transfer" }, transfer)).toBe(true);
    expect(matches({ ...f, kind: "income" }, income(3))).toBe(true);
  });

  it("filtre par catégorie, compte et montant", () => {
    const t = op(12.5, { categoryID: "groceries", accountID: "livret" });
    expect(matches({ ...emptyFilter(), categoryIDs: ["groceries"] }, t)).toBe(true);
    expect(matches({ ...emptyFilter(), categoryIDs: ["health"] }, t)).toBe(false);
    expect(matches({ ...emptyFilter(), accountID: "livret" }, t)).toBe(true);
    expect(matches({ ...emptyFilter(), accountID: "main" }, t)).toBe(false);
    expect(matches({ ...emptyFilter(), accountID: "main" }, expense(1))).toBe(true);
    expect(matches({ ...emptyFilter(), minCents: 1250 }, t)).toBe(true);
    expect(matches({ ...emptyFilter(), minCents: 1251 }, t)).toBe(false);
    expect(matches({ ...emptyFilter(), maxCents: 1249 }, t)).toBe(false);
    expect(isFilterActive({ ...emptyFilter(), maxCents: 1 })).toBe(true);
  });

  it("toggled", () => {
    expect(toggled(["a"], "b")).toEqual(["a", "b"]);
    expect(toggled(["a", "b"], "a")).toEqual(["b"]);
  });

  it("recherche sans casse ni accents (description, catégorie, tags)", async () => {
    const s = await makeStore();
    const tag = addTag(s, "Épargne");
    const t = { ...expense(3, "restaurants", day(2026, 10, 1)), note: "Déjeuner", tagIDs: [tag.id] };
    expect(foldText("Éléphant")).toBe("elephant");
    expect(matchesSearch(s, t, "dejeuner")).toBe(true);
    expect(matchesSearch(s, t, "RESTAU")).toBe(true);
    expect(matchesSearch(s, t, "epargne")).toBe(true);
    expect(matchesSearch(s, t, "autre chose")).toBe(false);
  });

  it("masque les opérations Izly", async () => {
    const s = await makeStore();
    const izly = newAccount({ name: "Izly", kind: "izly", colorIndex: 1 });
    s.accounts = [...s.accounts, izly];
    const meal = op(1, { accountID: izly.id });
    expect(isHiddenFromOperations(s, meal)).toBe(true);
    expect(isHiddenFromOperations(s, expense(1))).toBe(false);
    expect(izlySpending(s, [meal, meal, expense(5)])).toEqual({ count: 2, totalCents: 200 });
  });
});
