// Port de BudgetPlanningTests.swift, BudgetForecastTests.swift (partie budgets) et de la partie budgets de CategoryTests.
import { describe, expect, it } from "vitest";
import { day, expense, income, makeStore, tick } from "../test/support";
import { type BudgetStore } from "../store.svelte";
import { type Kind, newID, type RecurringOperation } from "../model";
import { startOfDay } from "../dates";
import { decodeSettings, encodeSettings } from "../codec";
import {
  budgetedCategories, budgetStatus, budgetStatuses, budgetTotals, daysRemaining, removeBudget, plannedBudget,
  setBudgetOverride, setBudgetPlan, setBudgetRollover, setMonthlyBudget, spentIn,
} from "./budgets";
import { annualBudgetBalance, applySuggestion, budgetSuggestions, monthPlan, projectedSpending, roundedBudget } from "./planning";

const now = day(2026, 10, 17);

function setBudget(s: BudgetStore, id: string, euros: number, rollover = false) {
  s.upsertCategory({ ...s.category(id), monthlyBudgetCents: euros * 100, budgetRollover: rollover ? true : null });
}

function recurring(name: string, euros: number, kind: Kind = "expense", categoryID = "otherExpense", start = now): RecurringOperation {
  return { id: newID(), name, amountCents: euros * 100, kind, categoryID, accountID: null, note: "", frequency: "monthly",
           startDate: start, endDate: null, isActive: true, lastGeneratedDate: null };
}

describe("budget du mois", () => {
  it("le budget d'un mois prime sur le budget par défaut", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100);
    setBudgetOverride(s, 15000, s.category("restaurants"), now);
    expect(plannedBudget(s.category("restaurants"), now)).toBe(15000);
    expect(plannedBudget(s.category("restaurants"), day(2026, 11, 1))).toBe(10000);

    // Un budget identique au budget par défaut n'est pas gardé.
    setBudgetOverride(s, 10000, s.category("restaurants"), now);
    expect(s.category("restaurants").budgetOverridesCents).toBeNull();

    // 0 = pas de budget ce mois-là.
    setBudgetOverride(s, 0, s.category("restaurants"), now);
    expect(budgetStatus(s, s.category("restaurants"), now)).toBeNull();
    expect(budgetedCategories(s, now).some(c => c.id === "restaurants")).toBe(false);
  });

  it("un budget de mois seul suffit à budgéter la catégorie", async () => {
    const s = await makeStore();
    setBudgetOverride(s, 8000, s.category("leisure"), now);
    expect(budgetStatus(s, s.category("leisure"), now)?.budget).toBe(8000);
    expect(budgetStatus(s, s.category("leisure"), day(2026, 11, 1))).toBeNull();
  });

  it("retirer le budget efface tout", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100, true);
    setBudgetOverride(s, 5000, s.category("restaurants"), day(2026, 12, 1));
    removeBudget(s, s.category("restaurants"));
    const c = s.category("restaurants");
    expect(c.monthlyBudgetCents).toBeNull();
    expect(c.budgetOverridesCents).toBeNull();
    expect(c.budgetRollover).toBeNull();
  });
});

describe("report", () => {
  it("reporte le reste et le dépassement dans l'année", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100, true);
    s.upsert(expense(10, "otherExpense", day(2026, 8, 3)));           // l'app est utilisée depuis août
    s.upsert(expense(60, "restaurants", day(2026, 8, 10)));           // +40
    s.upsert(expense(130, "restaurants", day(2026, 9, 10)));          // -30
    const status = budgetStatus(s, s.category("restaurants"), now);
    expect(status?.carryOver).toBe(1000);
    expect(status?.budget).toBe(11000);

    setBudgetRollover(s, false, s.category("restaurants"));
    expect(budgetStatus(s, s.category("restaurants"), now)?.budget).toBe(10000);
  });

  it("repart de zéro en janvier et ne rend jamais le budget négatif", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100, true);
    s.upsert(expense(400, "restaurants", day(2026, 12, 10)));
    expect(budgetStatus(s, s.category("restaurants"), day(2027, 1, 5))?.carryOver).toBe(0);

    s.upsert(expense(400, "restaurants", day(2026, 9, 10)));
    const october = budgetStatus(s, s.category("restaurants"), now);
    expect(october?.carryOver).toBe(-30000);
    expect(october?.budget).toBe(0);
    expect(october?.state).toBe("ok");
    s.upsert(expense(5, "restaurants", now));
    expect(budgetStatus(s, s.category("restaurants"), now)?.state).toBe("exceeded");
  });
});

describe("équilibre annuel", () => {
  it("détecte un dépassement rattrapé", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100);
    s.upsert(expense(150, "restaurants", day(2026, 8, 10)));   // -50
    s.upsert(expense(40, "restaurants", day(2026, 9, 10)));    // +60
    s.upsert(expense(80, "restaurants", day(2026, 10, 10)));   // +20 (en cours)
    const balance = annualBudgetBalance(s, now, now);
    const row = balance.rows.find(r => r.id === "restaurants")!;
    expect(row.counted.length).toBe(3);   // janvier → juillet : l'app n'était pas encore utilisée
    expect(row.balance).toBe(3000);
    expect(row.trend).toBe("recovered");
    expect(row.exceededMonths).toBe(1);
    expect(row.cells.filter(c => c.isFuture).length).toBe(2);
    expect(row.runningBalance.map(p => p.balance)).toEqual([-5000, 1000, 3000]);
    expect(balance.total.balance).toBe(3000);
  });

  it("calcule le budget à tenir pour rattraper", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100);
    s.upsert(expense(300, "restaurants", day(2026, 10, 10)));   // -200
    const row = annualBudgetBalance(s, now, now).rows.find(r => r.id === "restaurants")!;
    expect(row.trend).toBe("behind");
    // 2 mois restants à 100 € : il faut dépenser 0 € par mois pour rattraper 200 €.
    expect(row.catchUpPerMonth).toBe(0);
  });
});

describe("plan du mois", () => {
  it("exclut les récurrentes budgétées des charges fixes", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 200);
    s.recurringOperations = [
      recurring("Salaire", 1500, "income", "salary", day(2026, 1, 1)),
      recurring("Loyer", 600, "expense", "housing", day(2026, 1, 5)),
      recurring("Cantine", 50, "expense", "restaurants", day(2026, 1, 2)),
    ];
    setBudgetPlan(s, { savingsGoalCents: 30000, expectedIncomeCents: null });
    const plan = monthPlan(s, now, now);
    expect(plan.incomeSource).toBe("recurring");
    expect(plan.expectedIncomeCents).toBe(150000);
    expect(plan.fixedCharges.map(c => c.name)).toEqual(["Loyer"]);
    expect(plan.envelopesCents).toBe(20000);
    expect(plan.unallocatedCents).toBe((1500 - 600 - 200 - 300) * 100);

    setBudgetPlan(s, { savingsGoalCents: 30000, expectedIncomeCents: 200000 });
    expect(monthPlan(s, now, now).incomeSource).toBe("manual");
    expect(monthPlan(s, now, now).unallocatedCents).toBe(90000);
  });

  it("retombe sur la moyenne des revenus", async () => {
    const s = await makeStore();
    s.upsert(income(1000, day(2026, 8, 1), "otherIncome"));
    s.upsert(income(1200, day(2026, 9, 1), "otherIncome"));
    const plan = monthPlan(s, now, now);
    expect(plan.incomeSource).toBe("average");
    expect(plan.expectedIncomeCents).toBe(110000);
  });

  it("enregistre le plan et peut l'annuler", async () => {
    const s = await makeStore("/test/plan");
    setBudgetPlan(s, { savingsGoalCents: 25000, expectedIncomeCents: null });
    await s.flush();
    expect((await makeStore("/test/plan")).budgetPlan.savingsGoalCents).toBe(25000);
    await tick();
    s.undo();
    expect(s.budgetPlan.savingsGoalCents).toBeNull();
  });
});

describe("projection et suggestions", () => {
  it("combine le rythme et les récurrentes à venir", async () => {
    const s = await makeStore();
    s.upsert(expense(34, "groceries", day(2026, 10, 5)));   // 34 € en 17 jours = 2 €/jour
    s.recurringOperations = [recurring("Panier bio", 20, "expense", "groceries", day(2026, 1, 25))];
    const projected = projectedSpending(s, s.category("groceries"), now, now);
    // 34 + 2 × 14 jours restants + 20 (récurrente du 25)
    expect(projected).toBeCloseTo(8200, 6);
    expect(projectedSpending(s, s.category("groceries"), day(2026, 9, 1), now)).toBeNull();
  });

  it("propose des budgets d'après les 3 derniers mois", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 50);
    setBudget(s, "leisure", 300);
    for (const month of [7, 8, 9]) {
      s.upsert(expense(83, "groceries", day(2026, month, 10)));
      s.upsert(expense(90, "restaurants", day(2026, month, 10)));
      s.upsert(expense(40, "leisure", day(2026, month, 10)));
    }
    const suggestions = new Map(budgetSuggestions(s, now).map(x => [x.id, x]));
    expect(suggestions.get("groceries")?.reason).toBe("noBudget");
    expect(suggestions.get("groceries")?.suggestedCents).toBe(8500);
    expect(suggestions.get("restaurants")?.reason).toBe("tooLow");
    expect(suggestions.get("restaurants")?.suggestedCents).toBe(9000);
    expect(suggestions.get("leisure")?.reason).toBe("tooHigh");
    expect(suggestions.get("leisure")?.suggestedCents).toBe(4000);

    applySuggestion(s, suggestions.get("groceries")!);
    expect(s.category("groceries").monthlyBudgetCents).toBe(8500);
  });

  it("une opération à minuit le 1er n'appartient qu'à un mois", async () => {
    const s = await makeStore();
    s.upsert(expense(30, "restaurants", startOfDay(day(2026, 10, 1))));
    expect(s.transactionsInMonthOf(day(2026, 9, 15)).length).toBe(0);
    expect(s.transactionsInMonthOf(day(2026, 10, 15)).length).toBe(1);
    expect(spentIn(s, s.category("restaurants"), day(2026, 9, 15))).toBe(0);
  });

  it("arrondit les budgets proposés", () => {
    expect(roundedBudget(4230)).toBe(4500);
    expect(roundedBudget(4500)).toBe(4500);
    expect(roundedBudget(10100)).toBe(11000);
    expect(roundedBudget(0)).toBe(0);
  });

  it("relit d'anciennes catégories sans les nouveaux champs", () => {
    const settings = decodeSettings({ categories: [{ id: "x", label: "X", icon: "star", kind: "expense", colorIndex: 0, isHidden: false, monthlyBudget: 20 }] });
    const c = settings.categories.find(x => x.id === "x")!;
    expect(c.monthlyBudgetCents).toBe(2000);
    expect(c.budgetOverridesCents).toBeNull();
    expect(c.budgetRollover).toBeNull();
    expect(encodeSettings(settings)).toBeTruthy();
  });
});

describe("états et totaux des budgets", () => {
  it("passe de ok à attention puis dépassé", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100);
    const state = () => budgetStatus(s, s.category("restaurants"), now)?.state;
    expect(state()).toBe("ok");
    s.upsert(expense(79, "restaurants", now));
    expect(state()).toBe("ok");
    s.upsert(expense(1, "restaurants", now));
    expect(state()).toBe("warning");
    s.upsert(expense(20, "restaurants", now));
    expect(state()).toBe("warning");   // exactement 100 % n'est pas dépassé
    s.upsert(expense(1, "restaurants", now));
    const status = budgetStatus(s, s.category("restaurants"), now);
    expect(status?.state).toBe("exceeded");
    expect(status?.overspent).toBe(100);
    expect(status?.remaining).toBe(-100);
  });

  it("ignore les autres mois et les virements", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100);
    s.upsert(expense(50, "restaurants", day(2026, 9, 30)));
    s.upsert({ ...expense(500, "restaurants", now), transferID: newID() });
    expect(spentIn(s, s.category("restaurants"), now)).toBe(0);
  });

  it("sans budget, pas de statut", async () => {
    const s = await makeStore();
    expect(budgetStatus(s, s.category("restaurants"), now)).toBeNull();
    expect(budgetStatus(s, s.category("salary"), now)).toBeNull();
    setBudget(s, "restaurants", 100);
    setMonthlyBudget(s, null, s.category("restaurants"));
    expect(budgetedCategories(s).length).toBe(0);
  });

  it("totalise et trie du plus au moins consommé", async () => {
    const s = await makeStore();
    setBudget(s, "restaurants", 100);
    setBudget(s, "groceries", 200);
    s.upsert(expense(90, "restaurants", now));
    s.upsert(expense(20, "groceries", now));
    expect(budgetStatuses(s, now).map(x => x.category.id)).toEqual(["restaurants", "groceries"]);
    const totals = budgetTotals(s, now);
    expect([totals.spent, totals.budget, totals.remaining]).toEqual([11000, 30000, 19000]);
  });

  it("compte les jours restants", () => {
    expect(daysRemaining(now, now)).toBe(15);   // 17 → 31 octobre
    expect(daysRemaining(day(2026, 10, 31), day(2026, 10, 31))).toBe(1);
    expect(daysRemaining(day(2026, 9, 1), now)).toBe(0);
    expect(daysRemaining(day(2026, 11, 1), now)).toBe(30);
  });
});
