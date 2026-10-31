// Port de MealTests.swift (+ identifiant fixe vérifié contre CryptoKit).
import { describe, expect, it } from "vitest";
import { type Account, MAIN_ACCOUNT_ID, newAccount, type Transaction } from "../model";
import { day, makeStore, op, tick } from "../test/support";
import { balance, makeIzly, upsertAccount } from "./accounts";
import {
  addMeals, applyMealReview, generateDueMeals, isHiddenFromOperations, izlySpending, markMealsReviewed, mealID, mealReviewDays,
  mealsOf, mealsRemaining, needsMealReview, parseMealPrice, removeDuplicateAutoMeals, removeMeals,
} from "./meals";
import { sha1, toHex } from "./sha1";

const at = (y: number, m: number, d: number) => new Date(y, m - 1, d);
const monday = at(2026, 10, 5);
const friday2 = day(2026, 10, 16);

async function izlyStore(enabled = true) {
  const s = await makeStore();
  const base = makeIzly(s.accounts, 8, { id: "izly" });
  const account: Account = { ...base, mealPlan: { ...base.mealPlan!, startDate: monday, isEnabled: enabled } };
  upsertAccount(s, account);
  return { s, account };
}
const meals = (s: Awaited<ReturnType<typeof makeStore>>) => s.transactions.filter(t => t.isAutoMeal === true);

describe("SHA-1 et identifiant fixe", () => {
  it("SHA-1 : vecteurs connus", () => {
    const hex = (text: string) => toHex(sha1(new TextEncoder().encode(text)));
    expect(hex("abc")).toBe("a9993e364706816aba3e25717850c26c9cd0d89d");
    expect(hex("")).toBe("da39a3ee5e6b4b0d3255bfef95601890afd80709");
    expect(hex("a".repeat(1000))).toBe("291e9a6c66994949b57ba5e650361e98fc36b1ba");
  });

  it("identifiant identique à celui de l'app Mac (valeurs calculées avec CryptoKit)", () => {
    expect(mealID("izly", at(2026, 10, 5))).toBe("ABB50449-8112-5087-A98A-F40492B058C2");
    expect(mealID("main", at(2026, 1, 31))).toBe("A1DCE399-DD93-580D-B02D-E924FAC63A1C");
    expect(mealID("3F2504E0-4F89-11D3-9A0C-0305E82C3301", at(2025, 12, 9))).toBe("C2C6EF60-B150-5115-9823-CF85B1DE0EB2");
  });
});

describe("Repas Izly", () => {
  it("génère les jours ouvrés sur deux semaines", async () => {
    const { s } = await izlyStore();
    generateDueMeals(s, friday2);
    expect(meals(s)).toHaveLength(10);
    expect(meals(s).every(t => t.amountCents === 100 && t.accountID === "izly" && t.note === "Repas Crous")).toBe(true);
    expect(s.account("izly").mealPlan?.lastGeneratedDate?.getTime()).toBe(at(2026, 10, 16).getTime());
  });

  it("deux appareils créent les mêmes identifiants", async () => {
    const { s: mac } = await izlyStore();
    const { s: phone } = await izlyStore();
    generateDueMeals(mac, friday2);
    generateDueMeals(phone, friday2);
    expect(new Set(meals(mac).map(t => t.id))).toEqual(new Set(meals(phone).map(t => t.id)));
    expect(new Set(meals(mac).map(t => t.id)).size).toBe(10);
  });

  it("la suppression des doublons garde l'identifiant fixe", async () => {
    const { s } = await izlyStore();
    generateDueMeals(s, friday2);
    const fixed = meals(s)[0].id;
    s.upsert({ ...meals(s)[0], id: "11111111-1111-1111-1111-111111111111" });
    expect(meals(s)).toHaveLength(11);
    expect(removeDuplicateAutoMeals(s)).toBe(true);
    expect(meals(s)).toHaveLength(10);
    expect(meals(s).some(t => t.id === fixed)).toBe(true);
    expect(removeDuplicateAutoMeals(s)).toBe(false);
  });

  it("sans identifiant fixe, le plus petit est gardé", async () => {
    const { s } = await izlyStore();
    const a: Transaction = op(1, { id: "00000000-0000-0000-0000-000000000002", categoryID: "restaurants", note: "Repas Crous",
                                   date: day(2026, 10, 6), accountID: "izly", isAutoMeal: true });
    const b = { ...a, id: "00000000-0000-0000-0000-000000000001" };
    s.upsert(a); s.upsert(b);
    removeDuplicateAutoMeals(s);
    expect(meals(s).map(t => t.id)).toEqual([b.id]);
  });

  it("pas de doublon au second appel", async () => {
    const { s } = await izlyStore();
    generateDueMeals(s, friday2);
    generateDueMeals(s, friday2);
    expect(meals(s)).toHaveLength(10);
    generateDueMeals(s, day(2026, 10, 19));
    expect(meals(s)).toHaveLength(11);
  });

  it("pas de repas avant le début ni le week-end", async () => {
    const { s } = await izlyStore();
    generateDueMeals(s, day(2026, 10, 4));
    expect(meals(s)).toHaveLength(0);
    generateDueMeals(s, day(2026, 10, 11));
    expect(meals(s)).toHaveLength(5);
    expect(meals(s).some(t => [0, 6].includes(t.date.getDay()))).toBe(false);
  });

  it("un plan désactivé ne crée rien", async () => {
    const { s } = await izlyStore(false);
    generateDueMeals(s, friday2);
    expect(meals(s)).toHaveLength(0);
  });

  it("l'ajout en masse saute les jours déjà décomptés", async () => {
    const { s, account } = await izlyStore();
    generateDueMeals(s, day(2026, 10, 9));
    expect(addMeals(s, account, monday, day(2026, 10, 16), [2, 3, 4, 5, 6], 100)).toBe(5);
    expect(meals(s)).toHaveLength(10);
  });

  it("supprime des repas, annulable", async () => {
    const { s, account } = await izlyStore();
    generateDueMeals(s, friday2);
    await tick();
    const ids = new Set(meals(s).slice(0, 3).map(t => t.id));
    expect(removeMeals(s, ids)).toBe(3);
    expect(meals(s)).toHaveLength(7);
    s.undo();
    expect(meals(s)).toHaveLength(10);
    expect(mealsOf(s, account, { start: monday, end: day(2026, 10, 17) })).toHaveLength(10);
  });

  it("la revue est proposée après sept jours, puis marquée", async () => {
    const { s, account } = await izlyStore();
    generateDueMeals(s, day(2026, 10, 9));
    expect(needsMealReview(s, day(2026, 10, 9))).toBeNull();
    generateDueMeals(s, day(2026, 10, 12));
    expect(needsMealReview(s, day(2026, 10, 12))?.id).toBe("izly");
    markMealsReviewed(s, account, day(2026, 10, 12));
    expect(needsMealReview(s, day(2026, 10, 12))).toBeNull();
    expect(needsMealReview(s, day(2026, 10, 16))).toBeNull();
  });

  it("la revue s'applique en une seule annulation", async () => {
    const { s, account } = await izlyStore();
    generateDueMeals(s, day(2026, 10, 9));
    await tick();
    const days = mealReviewDays(s, s.account("izly"), day(2026, 10, 9));
    expect(days).toHaveLength(5);
    applyMealReview(s, account, days, days.slice(2), day(2026, 10, 9));
    expect(meals(s)).toHaveLength(3);
    expect(s.account("izly").mealPlan?.lastReviewDate).not.toBeNull();
    s.undo();
    expect(meals(s)).toHaveLength(5);
  });

  it("solde avec recharge et repas", async () => {
    const { s, account } = await izlyStore();
    s.transactions = [
      op(20, { kind: "expense", categoryID: "transfer", transferID: "T1", date: day(2026, 10, 5) }),
      op(20, { kind: "income", categoryID: "transfer", transferID: "T1", date: day(2026, 10, 5), accountID: "izly" }),
    ];
    generateDueMeals(s, friday2);
    expect(balance(s, account, day(2026, 10, 20))).toBe(1000);
    expect(mealsRemaining(s, s.account("izly"))).toBe(10);
  });

  it("les opérations Izly sont masquées dans Opérations", async () => {
    const { s } = await izlyStore();
    s.transactions = [
      op(20, { kind: "expense", categoryID: "transfer", transferID: "T1", date: day(2026, 10, 5) }),
      op(20, { kind: "income", categoryID: "transfer", transferID: "T1", date: day(2026, 10, 5), accountID: "izly" }),
    ];
    generateDueMeals(s, friday2);
    const visible = s.transactions.filter(t => !isHiddenFromOperations(s, t));
    expect(visible).toHaveLength(1);
    expect(visible[0].accountID ?? MAIN_ACCOUNT_ID).toBe(MAIN_ACCOUNT_ID);
    const summary = izlySpending(s, s.transactions);
    expect(summary.count).toBe(10);
    expect(summary.totalCents).toBe(1000);
  });

  it("un compte Izly sans plan reçoit le plan par défaut au chargement", async () => {
    const s = await makeStore();
    const izly = newAccount({ name: "Izly", kind: "izly", colorIndex: 3 });
    s.accounts = [...s.accounts, izly];
    s.saveSettings();
    await s.flush();
    const reloaded = await makeStore(s.directory);
    const plan = reloaded.accounts.find(a => a.id === izly.id)?.mealPlan;
    expect(plan?.isEnabled).toBe(true);
    expect(plan?.weekdays).toEqual([2, 3, 4, 5, 6]);
    expect(plan?.startDate.toDateString()).toBe(new Date().toDateString());
  });

  it("lit un prix saisi", () => {
    expect(parseMealPrice("1")).toBe(100);
    expect(parseMealPrice("1,50")).toBe(150);
    expect(parseMealPrice(" 2 ")).toBe(200);
    expect(parseMealPrice("")).toBeNull();
    expect(parseMealPrice("0")).toBeNull();
    expect(parseMealPrice("abc")).toBeNull();
  });
});
