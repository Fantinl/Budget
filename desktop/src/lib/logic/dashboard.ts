// Chiffres du tableau de bord (sans interface, testable). Port de DashboardSummary.swift. Montants en centimes.
import { type Account, DEFAULT_MEAL_PRICE_CENTS, familyOf, isEarning, isSpending, newID, type Transaction } from "../model";
import { addDays, isInMonth, startOfDay } from "../dates";
import type { BudgetStore } from "../store.svelte";
import { balance, totalBalance, value } from "./accounts";
import { occurrences, signedRecurring } from "./recurring";
import { type UpcomingRecurring, monthForecast } from "./forecast";
import { type BudgetStatus, type BudgetTotals, budgetStatuses, budgetedCategories, totalsOf } from "./budgets";

/// Sous cette limite, on invite à recharger Izly.
export const lowMealThreshold = 5;

export interface DashboardSummary {
  /// Comptes courants actifs et leur solde.
  currentAccounts: { account: Account; balanceCents: number }[];
  availableCents: number;
  monthIncomeCents: number;
  monthSpentCents: number;
  forecastCents: number;
  budgetTotals: BudgetTotals | null;
  topBudgets: BudgetStatus[];
  /// Compte Izly actif, son solde, le prix du repas et le nombre de repas restants.
  izly: { account: Account; balanceCents: number; mealPriceCents: number; meals: number } | null;
  savingsCents: number;
  wealthCents: number;
  upcoming: UpcomingRecurring[];
  latest: Transaction[];
  monthRemainingCents: number;
  izlyIsLow: boolean;
}

export function makeDashboardSummary(s: BudgetStore, now: Date = new Date()): DashboardSummary {
  const active = s.activeAccounts;
  const currentAccounts = active.filter(a => familyOf(a.kind) === "current").map(a => ({ account: a, balanceCents: balance(s, a) }));
  const available = currentAccounts.reduce((n, x) => n + x.balanceCents, 0);

  let monthIncome = 0;
  let monthSpent = 0;
  for (const t of s.transactions) {
    if (!isInMonth(t.date, now)) continue;
    if (isEarning(t)) monthIncome += t.amountCents;
    else if (isSpending(t)) monthSpent += t.amountCents;
  }
  const forecast = monthForecast(s, now).projectedCents;

  let totals: BudgetTotals | null = null;
  let topBudgets: BudgetStatus[] = [];
  if (budgetedCategories(s, now).length > 0) {
    const statuses = budgetStatuses(s, now);
    totals = totalsOf(statuses);
    topBudgets = statuses.slice(0, 3);
  }

  let izly: DashboardSummary["izly"] = null;
  const izlyAccount = active.find(a => a.kind === "izly");
  if (izlyAccount) {
    const b = balance(s, izlyAccount);
    const configured = izlyAccount.mealPlan?.priceCents ?? DEFAULT_MEAL_PRICE_CENTS;
    const price = configured > 0 ? configured : DEFAULT_MEAL_PRICE_CENTS;
    izly = { account: izlyAccount, balanceCents: b, mealPriceCents: price, meals: b > 0 ? Math.trunc(b / price) : 0 };
  }

  const savings = active
    .filter(a => familyOf(a.kind) === "savings" || familyOf(a.kind) === "investment")
    .reduce((n, a) => n + value(s, a), 0);

  // Récurrentes des 30 prochains jours (à partir de demain)
  const tomorrow = addDays(startOfDay(now), 1);
  const limit = addDays(startOfDay(now), 30);
  const coming: UpcomingRecurring[] = [];
  for (const operation of s.recurringOperations) {
    if (!operation.isActive) continue;
    const signed = signedRecurring(operation);
    for (const date of occurrences(operation, tomorrow, limit)) {
      coming.push({ id: newID(), name: operation.name, date, amountCents: signed });
    }
  }
  coming.sort((a, b) => a.date.getTime() - b.date.getTime());

  return {
    currentAccounts, availableCents: available, monthIncomeCents: monthIncome, monthSpentCents: monthSpent,
    forecastCents: forecast, budgetTotals: totals, topBudgets, izly, savingsCents: savings, wealthCents: totalBalance(s),
    upcoming: coming.slice(0, 5), latest: latestTransactions(s.transactions, 5),
    monthRemainingCents: monthIncome - monthSpent,
    izlyIsLow: (izly?.meals ?? Infinity) < lowMealThreshold,
  };
}

/// Les `n` opérations les plus récentes, sans trier tout le tableau (O(n·k)).
function latestTransactions(transactions: readonly Transaction[], n: number): Transaction[] {
  const top: Transaction[] = [];
  for (const t of transactions) {
    if (top.length === n && t.date.getTime() <= top[n - 1].date.getTime()) continue;
    let i = top.length < n ? top.length : n - 1;
    if (top.length < n) top.push(t); else top[n - 1] = t;
    while (i > 0 && top[i - 1].date.getTime() < top[i].date.getTime()) { [top[i - 1], top[i]] = [top[i], top[i - 1]]; i--; }
  }
  return top;
}
