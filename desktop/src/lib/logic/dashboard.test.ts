// Port de DashboardTests.swift.
import { describe, expect, it } from "vitest";
import { day, expense, income, makeStore } from "../test/support";
import { newAccount, newID, type RecurringOperation } from "../model";
import { startOfDay } from "../dates";
import { makeDashboardSummary } from "./dashboard";

const now = day(2026, 10, 17);

describe("tableau de bord", () => {
  it("l'argent disponible ne compte que les comptes courants", async () => {
    const s = await makeStore();
    s.accounts = [...s.accounts,
      newAccount({ name: "Livret", kind: "livretA", colorIndex: 1, initialBalanceCents: 50000 }),
      newAccount({ name: "Pocket", kind: "cash", colorIndex: 2, initialBalanceCents: 4000 })];
    s.upsert(income(1000, now));
    s.upsert(expense(200, "otherExpense", now));
    const summary = makeDashboardSummary(s, now);
    expect(summary.availableCents).toBe(80000);
    expect(summary.currentAccounts.length).toBe(1);
    expect(summary.savingsCents).toBe(50000);
    expect(summary.wealthCents).toBe(134000);
  });

  it("ignore un compte courant archivé", async () => {
    const s = await makeStore();
    const second = newAccount({ name: "Second", kind: "checking", colorIndex: 1, initialBalanceCents: 30000 });
    s.accounts = [...s.accounts, second];
    expect(makeDashboardSummary(s, now).availableCents).toBe(30000);
    s.accounts = s.accounts.map(a => (a.id === second.id ? { ...a, isArchived: true } : a));
    expect(makeDashboardSummary(s, now).availableCents).toBe(0);
  });

  it("le reste du mois exclut les virements", async () => {
    const s = await makeStore();
    const transferID = newID();
    s.upsert({ ...expense(100, "otherExpense", now), transferID });
    s.upsert({ ...income(100, now, "otherIncome"), transferID, accountID: "x" });
    s.upsert(income(1000, now, "otherIncome"));
    s.upsert(expense(250, "otherExpense", now));
    const summary = makeDashboardSummary(s, now);
    expect(summary.monthIncomeCents).toBe(100000);
    expect(summary.monthSpentCents).toBe(25000);
    expect(summary.monthRemainingCents).toBe(75000);
  });

  it("compte les repas Izly restants", async () => {
    const s = await makeStore();
    expect(makeDashboardSummary(s, now).izly).toBeNull();
    let izly = newAccount({ name: "Izly", kind: "izly", colorIndex: 3, initialBalanceCents: 1200 });
    izly = { ...izly, mealPlan: { isEnabled: true, priceCents: 300, weekdays: [2, 3, 4, 5, 6], categoryID: "restaurants", startDate: now, lastGeneratedDate: null, lastReviewDate: null } };
    s.accounts = [...s.accounts, izly];
    let summary = makeDashboardSummary(s, now);
    expect(summary.izly?.meals).toBe(4);
    expect(summary.izlyIsLow).toBe(true);

    izly = { ...izly, mealPlan: null, initialBalanceCents: 2000 };
    s.accounts = s.accounts.map(a => (a.id === izly.id ? izly : a));
    summary = makeDashboardSummary(s, now);
    expect(summary.izly?.meals).toBe(20);
    expect(summary.izlyIsLow).toBe(false);
    // Le compte Izly n'entre pas dans l'argent disponible
    expect(summary.availableCents).toBe(0);
  });

  it("montre les trois premiers budgets et les totaux", async () => {
    const s = await makeStore();
    expect(makeDashboardSummary(s, now).budgetTotals).toBeNull();
    for (const id of ["restaurants", "groceries", "transport", "leisure"]) s.upsertCategory({ ...s.category(id), monthlyBudgetCents: 10000 });
    s.upsert(expense(50, "restaurants", now));
    const summary = makeDashboardSummary(s, now);
    expect(summary.topBudgets.length).toBeLessThanOrEqual(3);
    expect(summary.topBudgets[0]?.category.id).toBe("restaurants");
    expect(summary.budgetTotals?.spent).toBe(5000);
  });

  it("liste les récurrentes sous 30 jours et les dernières opérations", async () => {
    const s = await makeStore();
    const rent: RecurringOperation = { id: newID(), name: "Loyer", amountCents: 50000, kind: "expense", categoryID: "otherExpense",
      accountID: null, note: "", frequency: "monthly", startDate: startOfDay(day(2026, 10, 25)), endDate: null, isActive: true, lastGeneratedDate: null };
    s.recurringOperations = [rent];
    for (let i = 1; i <= 7; i++) s.upsert(expense(i, "otherExpense", day(2026, 10, i)));
    const summary = makeDashboardSummary(s, now);
    expect(summary.upcoming.map(u => u.name)).toEqual(["Loyer"]);
    expect(summary.upcoming[0].amountCents).toBe(-50000);
    expect(summary.latest.length).toBe(5);
    expect(summary.latest[0].amountCents).toBe(700);
    expect(summary.latest.map(t => t.amountCents)).toEqual([700, 600, 500, 400, 300]);
  });
});
