// Port de BudgetForecastTests.swift (prévision de fin de mois).
import { describe, expect, it } from "vitest";
import { day, expense, income, makeStore } from "../test/support";
import { newID, type RecurringOperation, newAccount, MAIN_ACCOUNT_ID } from "../model";
import { startOfDay } from "../dates";
import { monthForecast, projectedBalance, upcomingRecurring } from "./forecast";

const now = day(2026, 10, 17);

function rec(name: string, euros: number, kind: "expense" | "income", categoryID: string, start: Date, isActive = true): RecurringOperation {
  return { id: newID(), name, amountCents: euros * 100, kind, categoryID, accountID: null, note: "", frequency: "monthly",
           startDate: start, endDate: null, isActive, lastGeneratedDate: null };
}

describe("prévision", () => {
  it("exclut les virements du solde du mois", async () => {
    const s = await makeStore();
    const livret = newAccount({ name: "L", kind: "livretA", colorIndex: 0 });
    s.accounts = [...s.accounts, livret];
    s.upsert(income(1000, day(2026, 10, 2)));
    s.upsert(expense(300, "otherExpense", day(2026, 10, 3)));
    const transferID = newID();
    s.upsert({ ...expense(200, "otherExpense", day(2026, 10, 4)), transferID });
    s.upsert({ ...income(200, day(2026, 10, 4)), transferID, accountID: livret.id });
    expect(monthForecast(s, now).currentCents).toBe(70000);
    expect(MAIN_ACCOUNT_ID).toBe("main");
  });

  it("demande deux mois d'historique", async () => {
    const s = await makeStore();
    s.upsert(expense(300, "otherExpense", day(2026, 9, 10)));
    expect(monthForecast(s, now).estimatedSpendingCents).toBeNull();
    s.upsert(expense(300, "otherExpense", day(2026, 8, 10)));
    const forecast = monthForecast(s, now);
    // 600 € sur août (31 j) + septembre (30 j) ; 15 jours restants, aujourd'hui exclu → 14.
    const daily = 60000 / 61;
    expect(forecast.dailyAverageCents).toBeCloseTo(daily, 6);
    expect(forecast.estimatedSpendingCents).toBeCloseTo(daily * 14, 6);
  });

  it("ignore les récurrentes dans l'historique", async () => {
    const s = await makeStore();
    s.upsert({ ...expense(300, "otherExpense", day(2026, 9, 10)), recurringID: newID() });
    s.upsert(expense(300, "otherExpense", day(2026, 8, 10)));
    expect(monthForecast(s, now).estimatedSpendingCents).toBeNull();
  });

  it("liste les récurrentes à venir et le solde prévu", async () => {
    const s = await makeStore();
    s.recurringOperations = [
      { ...rec("Loyer", 700, "expense", "housing", startOfDay(day(2026, 1, 25))), lastGeneratedDate: startOfDay(day(2026, 9, 25)) },
      rec("Salaire", 1800, "income", "salary", startOfDay(day(2026, 1, 28))),
      rec("Inactif", 5, "expense", "housing", startOfDay(day(2026, 1, 20)), false),
    ];
    s.upsert(income(100, day(2026, 10, 1)));
    const upcoming = upcomingRecurring(s, now);
    expect(upcoming.map(u => u.name)).toEqual(["Loyer", "Salaire"]);
    expect(upcoming.map(u => u.amountCents)).toEqual([-70000, 180000]);
    expect(monthForecast(s, now).projectedCents).toBe(100 * 100 + 1100 * 100);
    expect(projectedBalance(s, null, now)).toBe(100 * 100 + 1100 * 100);
  });

  it("n'annonce rien le dernier jour du mois", async () => {
    const s = await makeStore();
    s.recurringOperations = [rec("X", 1, "expense", "housing", startOfDay(day(2026, 1, 15)))];
    expect(upcomingRecurring(s, day(2026, 10, 31))).toEqual([]);
  });
});
