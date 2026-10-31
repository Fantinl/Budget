// Page Budget : plan du mois, équilibre de l'année, projection de fin de mois et suggestions.
// Port de BudgetStore+Planning.swift. Montants en centimes.

import { type Category, isEarning, isSpending, newID, type Transaction } from "../model";
import { addDays, addMonths, isInMonth, startOfDay, startOfMonth, startOfYear } from "../dates";
import type { BudgetStore } from "../store.svelte";
import { occurrences } from "./recurring";
import {
  balanceStart, budgetStatuses, daysRemaining, isCurrentMonth, MonthlySpending, plannedBudget, setMonthlyBudget,
} from "./budgets";

/// Origine des revenus prévus du mois.
export type PlannedIncomeSource = "manual" | "recurring" | "average" | "none";

export const incomeSourceLabel: Record<PlannedIncomeSource, string> = {
  manual: "Saisis à la main",
  recurring: "D'après tes revenus récurrents",
  average: "Moyenne des 3 derniers mois",
  none: "Aucun revenu connu",
};

/// Charge fixe du mois : une échéance de récurrente dont la catégorie n'a pas de budget.
export interface PlannedCharge {
  id: string;
  name: string;
  categoryID: string;
  date: Date;
  amountCents: number;
}

/// Plan d'un mois : revenus prévus − charges fixes − enveloppes − épargne = reste à répartir.
export interface MonthPlan {
  month: Date;
  expectedIncomeCents: number;
  incomeSource: PlannedIncomeSource;
  /// Charges fixes (récurrentes de dépense hors catégories budgétées), triées par date.
  fixedCharges: PlannedCharge[];
  fixedTotalCents: number;
  /// Somme des budgets disponibles des catégories (report compris).
  envelopesCents: number;
  savingsGoalCents: number;
  /// Réalisé : revenus et dépenses du mois (hors virements).
  actualIncomeCents: number;
  actualSpentCents: number;
  /// Dépenses du mois dans des catégories sans budget (charges fixes comprises).
  unbudgetedSpentCents: number;
  /// Reste à répartir (négatif = plan déficitaire).
  unallocatedCents: number;
  /// Épargne réelle du mois à ce jour.
  actualSavingsCents: number;
}

/// Une case de l'équilibre annuel : une catégorie (ou le total) sur un mois.
export interface AnnualBudgetCell {
  month: Date;
  planned: number;
  spent: number;
  /// Mois compté dans l'équilibre (écoulé ou en cours, et après le début d'utilisation de l'app).
  isCounted: boolean;
  isCurrent: boolean;
  /// Mois pas encore commencé.
  isFuture: boolean;
  /// Écart du mois : positif = économie, négatif = dépassement.
  difference: number;
}

/// Tendance de l'année pour une catégorie.
export type AnnualBudgetTrend = "onTrack" | "recovered" | "behind";

export const trendLabel: Record<AnnualBudgetTrend, string> = {
  onTrack: "Dans les clous",
  recovered: "Rattrapé",
  behind: "À rattraper",
};

/// Ligne de l'équilibre annuel (une catégorie budgétée, ou le total si `category` est null).
export interface AnnualBudgetRow {
  id: string;
  category: Category | null;
  /// Les 12 mois de l'année.
  cells: AnnualBudgetCell[];
  counted: AnnualBudgetCell[];
  /// Cumul (budget − dépensé) des mois comptés : positif = d'avance, négatif = en retard.
  balance: number;
  plannedToDate: number;
  spentToDate: number;
  /// Budget de l'année entière (mois comptés + mois à venir).
  plannedYear: number;
  /// Mois dépassés parmi les mois comptés.
  exceededMonths: number;
  trend: AnnualBudgetTrend;
  /// Cumul à la fin de chaque mois compté (pour la courbe).
  runningBalance: { month: Date; balance: number }[];
  /// Budget mensuel moyen à respecter sur les mois restants pour finir l'année à l'équilibre.
  /// null s'il ne reste aucun mois ou si la catégorie est déjà à l'équilibre.
  catchUpPerMonth: number | null;
}

function makeCell(month: Date, planned: number, spent: number, firstCounted: Date, currentMonth: Date): AnnualBudgetCell {
  const t = month.getTime();
  return { month, planned, spent, isCounted: t >= firstCounted.getTime() && t <= currentMonth.getTime(),
           isCurrent: t === currentMonth.getTime(), isFuture: t > currentMonth.getTime(), difference: planned - spent };
}

export function makeAnnualRow(category: Category | null, cells: AnnualBudgetCell[]): AnnualBudgetRow {
  const counted = cells.filter(c => c.isCounted);
  const balance = counted.reduce((n, c) => n + c.difference, 0);
  const exceededMonths = counted.filter(c => c.difference < 0).length;
  let running = 0;
  const remaining = cells.filter(c => c.isFuture);
  let catchUp: number | null = null;
  if (balance < 0 && remaining.length > 0) {
    catchUp = Math.max(0, (remaining.reduce((n, c) => n + c.planned, 0) + balance) / remaining.length);
  }
  return {
    id: category?.id ?? "total", category, cells, counted, balance,
    plannedToDate: counted.reduce((n, c) => n + c.planned, 0),
    spentToDate: counted.reduce((n, c) => n + c.spent, 0),
    plannedYear: cells.filter(c => c.isCounted || c.isFuture).reduce((n, c) => n + c.planned, 0),
    exceededMonths,
    trend: balance < 0 ? "behind" : exceededMonths > 0 ? "recovered" : "onTrack",
    runningBalance: counted.map(c => { running += c.difference; return { month: c.month, balance: running }; }),
    catchUpPerMonth: catchUp,
  };
}

/// Équilibre de l'année : chaque catégorie budgétée, mois par mois, et le total.
export interface AnnualBudgetBalance {
  year: Date;
  rows: AnnualBudgetRow[];
  total: AnnualBudgetRow;
}

/// Proposition de budget tirée des dépenses des derniers mois.
export type SuggestionReason = "noBudget" | "tooLow" | "tooHigh";

export const suggestionReasonLabel: Record<SuggestionReason, string> = {
  noBudget: "Pas encore de budget",
  tooLow: "Souvent dépassé",
  tooHigh: "Largement sous-utilisé",
};

export interface BudgetSuggestion {
  id: string;
  category: Category;
  reason: SuggestionReason;
  /// Budget par défaut actuel (null = aucun).
  currentCents: number | null;
  /// Moyenne mensuelle des mois analysés.
  averageCents: number;
  suggestedCents: number;
  monthsAnalysed: number;
}

const inMonthOf = (transactions: readonly Transaction[], month: Date) => transactions.filter(t => isInMonth(t.date, month));
const sum = (list: readonly Transaction[]) => list.reduce((n, t) => n + t.amountCents, 0);

// MARK: - Plan du mois

export function monthPlan(s: BudgetStore, month: Date, _now: Date = new Date()): MonthPlan {
  const monthStart = startOfMonth(month);
  const lastDay = addDays(addMonths(monthStart, 1), -1);
  const monthTransactions = inMonthOf(s.transactions, monthStart);
  const statuses = budgetStatuses(s, monthStart);
  const budgeted = new Set(statuses.map(x => x.id));

  const charges: PlannedCharge[] = [];
  let recurringIncome = 0;
  for (const operation of s.recurringOperations) {
    if (!operation.isActive) continue;
    const dates = occurrences(operation, monthStart, lastDay);
    if (operation.kind === "income") {
      recurringIncome += operation.amountCents * dates.length;
    } else if (!budgeted.has(operation.categoryID)) {
      for (const date of dates) {
        charges.push({ id: newID(), name: operation.name, categoryID: operation.categoryID, date, amountCents: operation.amountCents });
      }
    } // sinon : déjà compté dans l'enveloppe de sa catégorie
  }

  let income = 0;
  let source: PlannedIncomeSource = "none";
  const manual = s.budgetPlan.expectedIncomeCents;
  if (manual !== null && manual > 0) { income = manual; source = "manual"; }
  else if (recurringIncome > 0) { income = recurringIncome; source = "recurring"; }
  else {
    const average = averageIncome(s, monthStart);
    if (average !== null) { income = average; source = "average"; }
  }

  const actualIncome = sum(monthTransactions.filter(isEarning));
  const spending = monthTransactions.filter(isSpending);
  const fixedCharges = charges.sort((a, b) => a.date.getTime() - b.date.getTime());
  const fixedTotal = fixedCharges.reduce((n, c) => n + c.amountCents, 0);
  const envelopes = statuses.reduce((n, x) => n + x.budget, 0);
  const savingsGoal = Math.max(0, s.budgetPlan.savingsGoalCents ?? 0);
  const actualSpent = sum(spending);
  return {
    month: monthStart, expectedIncomeCents: income, incomeSource: source, fixedCharges, fixedTotalCents: fixedTotal,
    envelopesCents: envelopes, savingsGoalCents: savingsGoal, actualIncomeCents: actualIncome, actualSpentCents: actualSpent,
    unbudgetedSpentCents: sum(spending.filter(t => !budgeted.has(t.categoryID))),
    unallocatedCents: income - fixedTotal - envelopes - savingsGoal,
    actualSavingsCents: actualIncome - actualSpent,
  };
}

/// Moyenne des revenus des 3 mois précédant `month` qui en ont, null s'il n'y en a aucun.
export function averageIncome(s: BudgetStore, month: Date): number | null {
  const totals = [1, 2, 3]
    .map(back => sum(inMonthOf(s.transactions, addMonths(month, -back)).filter(isEarning)))
    .filter(x => x > 0);
  if (totals.length === 0) return null;
  return totals.reduce((a, b) => a + b, 0) / totals.length;
}

// MARK: - Équilibre de l'année

export function annualBudgetBalance(s: BudgetStore, year: Date, now: Date = new Date()): AnnualBudgetBalance {
  const yearStart = startOfYear(year);
  const months = Array.from({ length: 12 }, (_, i) => addMonths(yearStart, i));
  const firstCounted = balanceStart(s, yearStart);
  const currentMonth = startOfMonth(now);
  const spending = new MonthlySpending(s.transactions, yearStart, addMonths(yearStart, 12));

  const categoriesInYear = s.categories.filter(c => c.kind === "expense" && months.some(m => plannedBudget(c, m) > 0));
  const rows = categoriesInYear
    .map(c => makeAnnualRow(c, months.map(m => makeCell(m, plannedBudget(c, m), spending.spent(c.id, m), firstCounted, currentMonth))))
    .sort((a, b) => a.balance - b.balance);   // les plus en retard d'abord

  const totalCells = months.map((m, i) =>
    makeCell(m, rows.reduce((n, r) => n + r.cells[i].planned, 0), rows.reduce((n, r) => n + r.cells[i].spent, 0), firstCounted, currentMonth));
  return { year: yearStart, rows, total: makeAnnualRow(null, totalCells) };
}

// MARK: - Projection de fin de mois

/// Dépense estimée d'une catégorie en fin de mois (mois en cours seulement) :
/// déjà dépensé + rythme des dépenses ponctuelles sur les jours restants + récurrentes à venir.
export function projectedSpending(s: BudgetStore, category: Category, month: Date, now: Date = new Date()): number | null {
  if (!isCurrentMonth(month, now)) return null;
  const spending = inMonthOf(s.transactions, month).filter(t => isSpending(t) && t.categoryID === category.id);
  const spent = sum(spending);
  const elapsedDays = now.getDate();
  const remainingDays = daysRemaining(month, now) - 1;   // aujourd'hui est déjà compté
  const oneOff = sum(spending.filter(t => t.recurringID === null));
  const pace = elapsedDays > 0 ? (oneOff / elapsedDays) * Math.max(0, remainingDays) : 0;

  let upcoming = 0;
  const tomorrow = addDays(startOfDay(now), 1);
  const lastDay = addDays(addMonths(startOfMonth(month), 1), -1);
  if (tomorrow.getTime() <= lastDay.getTime()) {
    for (const operation of s.recurringOperations) {
      if (operation.isActive && operation.kind === "expense" && operation.categoryID === category.id) {
        upcoming += operation.amountCents * occurrences(operation, tomorrow, lastDay).length;
      }
    }
  }
  return spent + pace + upcoming;
}

// MARK: - Suggestions

/// Arrondi « lisible » vers le haut : à 5 € sous 100 €, à 10 € au-delà. Entrée et sortie en centimes.
export function roundedBudget(cents: number): number {
  if (!(cents > 0)) return 0;
  const euros = cents / 100;
  const step = euros < 100 ? 5 : 10;
  return Math.round(Math.ceil(euros / step - 1e-9) * step * 100);
}

/// Budgets proposés d'après les 3 mois complets précédents (ceux qui ont des opérations).
export function budgetSuggestions(s: BudgetStore, now: Date = new Date()): BudgetSuggestion[] {
  const current = startOfMonth(now);
  const months = [1, 2, 3].map(back => addMonths(current, -back));
  const spending = new MonthlySpending(s.transactions, addMonths(current, -3), current);
  const analysed = months.filter(m => spending.hasData(m));
  if (analysed.length === 0) return [];

  const result: BudgetSuggestion[] = [];
  for (const category of s.categories) {
    if (category.kind !== "expense" || category.isHidden) continue;
    const amounts = analysed.map(m => spending.spent(category.id, m));
    const average = amounts.reduce((a, b) => a + b, 0) / analysed.length;
    const budget = category.monthlyBudgetCents ?? 0;
    let reason: SuggestionReason;
    if (budget <= 0) {
      if (!(average >= 1000)) continue;
      reason = "noBudget";
    } else if (analysed.length >= 2 && amounts.filter(x => x > budget).length * 2 > analysed.length && average > budget * 1.05) {
      reason = "tooLow";
    } else if (analysed.length >= 2 && average < budget * 0.6) {
      reason = "tooHigh";
    } else {
      continue;
    }
    const suggested = roundedBudget(average);
    if (!(suggested > 0) || suggested === budget) continue;
    result.push({ id: category.id, category, reason, currentCents: budget > 0 ? budget : null, averageCents: average,
                  suggestedCents: suggested, monthsAnalysed: analysed.length });
  }
  return result.sort((a, b) => b.averageCents - a.averageCents);
}

/// Applique une suggestion comme nouveau budget par défaut.
export function applySuggestion(s: BudgetStore, suggestion: BudgetSuggestion) {
  setMonthlyBudget(s, suggestion.suggestedCents, suggestion.category);
}
