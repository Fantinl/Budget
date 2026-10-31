// Port de StatsDrillDownTests.swift, PerformanceTests.swift (adapté) et de tests de Stats.swift.
import { describe, expect, it } from "vitest";
import { day, expense, income, makeStore, op } from "../test/support";
import { newID } from "../model";
import { startOfDay } from "../dates";
import { categoryTransactions, makeStatsSnapshot } from "./stats";
import { monthForecast } from "./forecast";
import { balance } from "./accounts";

describe("détail d'une catégorie", () => {
  it("liste les dépenses de la période, la plus récente d'abord", () => {
    const all = [
      expense(10, "restaurants", day(2026, 10, 3)),
      expense(20, "restaurants", day(2026, 10, 12)),
      expense(5, "groceries", day(2026, 10, 5)),
      expense(99, "restaurants", day(2026, 9, 30)),
      expense(98, "restaurants", day(2026, 11, 1)),
      income(50, day(2026, 10, 6), "restaurants"),
      { ...expense(30, "restaurants", day(2026, 10, 9)), transferID: newID() },
    ];
    const result = categoryTransactions("restaurants", all, startOfDay(day(2026, 10, 1)), startOfDay(day(2026, 11, 1)));
    expect(result.map(t => t.amountCents)).toEqual([2000, 1000]);
  });

  it("le filtre par compte est appliqué par l'appelant", () => {
    const all = [expense(10, "restaurants", day(2026, 10, 3)), expense(20, "restaurants", day(2026, 10, 4))];
    all[0] = { ...all[0], accountID: "a" };
    const filtered = all.filter(t => (t.accountID ?? "main") === "a");
    expect(categoryTransactions("restaurants", filtered, startOfDay(day(2026, 10, 1)), startOfDay(day(2026, 11, 1))).length).toBe(1);
  });
});

describe("statistiques", () => {
  const now = day(2026, 10, 16);
  const cat = (id: string) => ({ id, label: id, icon: "star", kind: "expense" as const, colorIndex: 0, isHidden: false,
                                 monthlyBudgetCents: null, budgetOverridesCents: null, budgetRollover: null });

  it("compare à la même date de la période précédente", () => {
    const tx = [
      expense(100, "a", day(2026, 10, 5)), expense(50, "a", day(2026, 10, 20)),
      expense(80, "a", day(2026, 9, 10)), expense(500, "a", day(2026, 9, 25)),
      income(300, day(2026, 10, 2)),
    ];
    const snap = makeStatsSnapshot(tx, "month", 0, cat, now);
    expect(snap.expensesCents).toBe(15000);
    expect(snap.incomeCents).toBe(30000);
    expect(snap.balanceCents).toBe(15000);
    // 1er–16 septembre : 80 € → (150 − 80) / 80
    expect(snap.expenseChange).toBeCloseTo(0.875, 6);
    expect(snap.categories.map(c => [c.id, c.share])).toEqual([["a", 1]]);
    expect(snap.months.length).toBe(12);
    expect(snap.topExpenses.map(t => t.amountCents)).toEqual([10000, 5000]);
  });

  it("couvre toutes les données pour « Tout » et exclut les virements des graphiques", () => {
    const tx = [expense(10, "a", day(2025, 3, 5)), { ...expense(40, "a", day(2026, 5, 5)), transferID: newID() }];
    const snap = makeStatsSnapshot(tx, "all", 0, cat, now);
    expect(snap.start).toEqual(new Date(2025, 2, 1));
    expect(snap.end).toEqual(new Date(2026, 10, 1));
    expect(snap.expensesCents).toBe(1000);
    expect(snap.expenseChange).toBeNull();
    expect(snap.monthlyExpenses.length).toBe(1);
    expect(snap.averagePerMonthCents).toBeCloseTo(1000 / 20, 6);
  });
});

describe("performance (5 000 opérations)", () => {
  const now = day(2026, 10, 15);
  async function large() {
    const s = await makeStore();
    const categories = s.categoriesFor("expense").map(c => c.id);
    const start = new Date(now.getFullYear() - 3, now.getMonth(), now.getDate()).getTime();
    const span = now.getTime() - start;
    s.transactions = Array.from({ length: 5000 }, (_, i) =>
      op((i % 97) + 0.5, { kind: i % 10 === 0 ? "income" : "expense", categoryID: categories[i % categories.length],
                           note: `Opération ${i}`, date: new Date(start + (span * i) / 5000) }));
    return s;
  }
  function timed<T>(name: string, block: () => T): T {
    const t0 = performance.now();
    const r = block();
    const ms = performance.now() - t0;
    console.log(`PERF ${name}: ${ms.toFixed(1)} ms`);
    expect(ms, `${name} trop lent`).toBeLessThan(1000);
    return r;
  }

  it("requêtes et statistiques restent rapides", async () => {
    const s = await large();
    expect(timed("transactionsInMonthOf", () => s.transactionsInMonthOf(now)).length).toBeGreaterThan(0);
    const snap = timed("StatsSnapshot sur l'année", () => makeStatsSnapshot(s.transactions, "year", 0, s.category.bind(s), now));
    expect(snap.hasData).toBe(true);
    const forecast = timed("monthForecast", () => monthForecast(s, now));
    expect(forecast.estimatedSpendingCents).not.toBeNull();
    timed("solde du compte", () => balance(s, s.account("main")));
    timed("statistiques « Tout »", () => makeStatsSnapshot(s.transactions, "all", 0, s.category.bind(s), now));
  });
});
