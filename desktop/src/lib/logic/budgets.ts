// Budgets mensuels par catégorie. Port de BudgetStore+Budgets.swift.
// Calculés sur tous les comptes, virements exclus. Montants en centimes (les moyennes peuvent être fractionnaires).

import { type Category, isSpending, type Transaction } from "../model";
import { addMonths, daysInMonth, isInMonth, monthKey, startOfMonth, startOfYear } from "../dates";
import type { BudgetStore } from "../store.svelte";

/// État d'un budget : < 80 % ok, 80–100 % attention, > 100 % dépassé.
export type BudgetState = "ok" | "warning" | "exceeded";

/// Situation d'une catégorie budgétée sur un mois.
export interface BudgetStatus {
  /// Identifiant de la catégorie.
  id: string;
  category: Category;
  spent: number;
  /// Budget prévu pour ce mois (budget du mois s'il existe, sinon budget par défaut).
  planned: number;
  /// Report des mois précédents de l'année (positif = reste, négatif = dépassement), 0 sans report.
  carryOver: number;
  /// Montant disponible ce mois : budget prévu + report (jamais négatif).
  budget: number;
  /// Reste à dépenser (négatif si dépassé).
  remaining: number;
  ratio: number;
  state: BudgetState;
  overspent: number;
}

export function makeBudgetStatus(category: Category, spent: number, planned: number, carryOver = 0): BudgetStatus {
  const budget = Math.max(0, planned + carryOver);
  // Report qui a tout absorbé : la moindre dépense dépasse
  const ratio = budget > 0 ? spent / budget : spent > 0 ? 2 : 0;
  const state: BudgetState = ratio > 1 ? "exceeded" : ratio >= 0.8 ? "warning" : "ok";
  return { id: category.id, category, spent, planned, carryOver, budget, remaining: budget - spent, ratio, state,
           overspent: Math.max(0, spent - budget) };
}

/// Totaux sur l'ensemble des catégories budgétées.
export interface BudgetTotals {
  spent: number;
  budget: number;
  remaining: number;
  ratio: number;
}

export function makeBudgetTotals(spent: number, budget: number): BudgetTotals {
  return { spent, budget, remaining: budget - spent, ratio: budget > 0 ? spent / budget : 0 };
}

const monthIndex = (d: Date) => d.getFullYear() * 12 + d.getMonth();

/// Dépenses (hors virements) par catégorie et par mois, calculées en une seule passe sur les opérations.
export class MonthlySpending {
  /// Identifiant de catégorie → index de mois → montant dépensé.
  private amounts = new Map<string, Map<number, number>>();
  /// Mois ayant au moins une opération (dépense, revenu ou virement).
  private monthsWithData = new Set<number>();

  constructor(transactions: readonly Transaction[], start: Date, end: Date) {
    const lo = start.getTime();
    const hi = end.getTime();
    for (const t of transactions) {
      const time = t.date.getTime();
      if (time < lo || time >= hi) continue;
      const key = monthIndex(t.date);
      this.monthsWithData.add(key);
      if (isSpending(t)) {
        let byMonth = this.amounts.get(t.categoryID);
        if (!byMonth) { byMonth = new Map(); this.amounts.set(t.categoryID, byMonth); }
        byMonth.set(key, (byMonth.get(key) ?? 0) + t.amountCents);
      }
    }
  }

  spent(categoryID: string, month: Date): number {
    return this.amounts.get(categoryID)?.get(monthIndex(month)) ?? 0;
  }

  hasData(month: Date): boolean { return this.monthsWithData.has(monthIndex(month)); }
}

/// Montant arrondi à l'euro près si possible (« 120 € », « 12,50 € »).
const budgetFormat = new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR", minimumFractionDigits: 0, maximumFractionDigits: 2 });
export const budgetEuros = (cents: number) => budgetFormat.format(cents / 100);

// Date la plus ancienne, gardée par tableau d'opérations (les tableaux du magasin ne sont jamais modifiés en place).
const earliestCache = new WeakMap<readonly Transaction[], Date | null>();
function earliestDate(transactions: readonly Transaction[]): Date | null {
  let cached = earliestCache.get(transactions);
  if (cached === undefined) {
    let min = Infinity;
    for (const t of transactions) { const x = t.date.getTime(); if (x < min) min = x; }
    cached = min === Infinity ? null : new Date(min);
    earliestCache.set(transactions, cached);
  }
  return cached;
}

/// Dépenses (hors virements) d'une catégorie sur le mois de `month`, tous comptes.
export function spentIn(s: BudgetStore, category: Category, month: Date): number {
  let total = 0;
  for (const t of s.transactions) {
    if (isSpending(t) && t.categoryID === category.id && isInMonth(t.date, month)) total += t.amountCents;
  }
  return total;
}

/// Budget prévu d'une catégorie pour un mois : budget de ce mois s'il existe, sinon budget par défaut.
export function plannedBudget(category: Category, month: Date): number {
  if (category.kind !== "expense") return 0;
  const override = category.budgetOverridesCents?.[monthKey(month)];
  if (override !== undefined) return Math.max(0, override);
  return Math.max(0, category.monthlyBudgetCents ?? 0);
}

/// Vrai si la catégorie a un budget propre à ce mois (différent du budget par défaut).
export function hasBudgetOverride(category: Category, month: Date): boolean {
  return category.budgetOverridesCents?.[monthKey(month)] !== undefined;
}

/// Catégories de dépense ayant un budget > 0 ce mois-ci (visibles ou non, tant qu'un budget existe).
export function budgetedCategories(s: BudgetStore, month: Date = new Date()): Category[] {
  return s.categories.filter(c => plannedBudget(c, month) > 0);
}

/// Premier mois compté dans l'équilibre de l'année de `month` : janvier, ou le premier mois
/// avec des opérations s'il est plus tard (les mois d'avant l'utilisation de l'app ne comptent pas).
export function balanceStart(s: BudgetStore, month: Date): Date {
  const yearStart = startOfYear(month);
  const first = earliestDate(s.transactions);
  if (!first) return yearStart;
  const firstMonth = startOfMonth(first);
  return firstMonth.getTime() > yearStart.getTime() ? firstMonth : yearStart;
}

/// Report d'une catégorie au début de `month` : somme (budget prévu − dépensé) des mois précédents
/// de la même année. 0 si le report n'est pas activé.
export function carryOver(s: BudgetStore, category: Category, month: Date, spending?: MonthlySpending): number {
  if (category.budgetRollover !== true) return 0;
  const monthStart = startOfMonth(month);
  let cursor = balanceStart(s, monthStart);
  if (cursor.getTime() >= monthStart.getTime()) return 0;
  const index = spending ?? new MonthlySpending(s.transactions, cursor, monthStart);
  let total = 0;
  while (cursor.getTime() < monthStart.getTime()) {
    total += plannedBudget(category, cursor) - index.spent(category.id, cursor);
    cursor = addMonths(cursor, 1);
  }
  return total;
}

/// Index des dépenses du début de l'année de `month` jusqu'à la fin de ce mois.
export function yearSpending(s: BudgetStore, month: Date): MonthlySpending {
  const start = balanceStart(s, month);
  const end = addMonths(startOfMonth(month), 1);
  const ms = startOfMonth(month);
  return new MonthlySpending(s.transactions, start.getTime() < ms.getTime() ? start : ms, end);
}

function statusWith(s: BudgetStore, category: Category, month: Date, spending: MonthlySpending): BudgetStatus | null {
  const planned = plannedBudget(category, month);
  if (!(planned > 0)) return null;
  return makeBudgetStatus(category, spending.spent(category.id, month), planned, carryOver(s, category, month, spending));
}

export function budgetStatus(s: BudgetStore, category: Category, month: Date): BudgetStatus | null {
  return statusWith(s, category, month, yearSpending(s, month));
}

/// Statuts de toutes les catégories budgétées, du plus consommé au moins consommé.
export function budgetStatuses(s: BudgetStore, month: Date): BudgetStatus[] {
  const spending = yearSpending(s, month);
  const result: BudgetStatus[] = [];
  for (const c of budgetedCategories(s, month)) {
    const status = statusWith(s, c, month, spending);
    if (status) result.push(status);
  }
  return result.sort((a, b) => b.ratio - a.ratio);
}

export function totalsOf(statuses: readonly BudgetStatus[]): BudgetTotals {
  return makeBudgetTotals(statuses.reduce((n, x) => n + x.spent, 0), statuses.reduce((n, x) => n + x.budget, 0));
}

export function budgetTotals(s: BudgetStore, month: Date): BudgetTotals {
  return totalsOf(budgetStatuses(s, month));
}

/// Jours restants dans le mois, aujourd'hui compris (0 pour un mois passé, tout le mois pour un mois futur).
export function daysRemaining(month: Date, now: Date = new Date()): number {
  const start = startOfMonth(month);
  const end = addMonths(start, 1);
  const total = daysInMonth(month);
  if (now.getTime() < start.getTime()) return total;
  if (now.getTime() >= end.getTime()) return 0;
  return Math.max(0, total - now.getDate() + 1);
}

/// Part du mois écoulée (0 pour un mois futur, 1 pour un mois passé), aujourd'hui compris.
export function elapsedFraction(month: Date, now: Date = new Date()): number {
  const total = daysInMonth(month);
  return (total - daysRemaining(month, now) + (isCurrentMonth(month, now) ? 1 : 0)) / total;
}

export function isCurrentMonth(month: Date, now: Date = new Date()): boolean {
  return isInMonth(month, now);
}

// MARK: - Modifications

function updateCategory(s: BudgetStore, id: string, undoName: string, change: (c: Category) => Category) {
  const index = s.categories.findIndex(c => c.id === id);
  if (index < 0) return;
  s.registerUndo(undoName);
  s.categories = s.categories.with(index, change(s.categories[index]));
  s.saveSettings();
}

/// Fixe (ou retire, avec null) le budget mensuel par défaut d'une catégorie.
export function setMonthlyBudget(s: BudgetStore, cents: number | null, category: Category) {
  updateCategory(s, category.id, "Modifier le budget", c => ({ ...c, monthlyBudgetCents: (cents ?? 0) > 0 ? cents : null }));
}

/// Budget d'une catégorie pour un seul mois. null = revenir au budget par défaut ; 0 = pas de budget ce mois-là.
export function setBudgetOverride(s: BudgetStore, cents: number | null, category: Category, month: Date) {
  updateCategory(s, category.id, "Modifier le budget du mois", c => {
    const overrides = { ...(c.budgetOverridesCents ?? {}) };
    const key = monthKey(month);
    if (cents !== null && Math.max(0, cents) !== (c.monthlyBudgetCents ?? 0)) overrides[key] = Math.max(0, cents);
    else delete overrides[key];   // identique au budget par défaut : inutile de le garder
    return { ...c, budgetOverridesCents: Object.keys(overrides).length === 0 ? null : overrides };
  });
}

/// Retire tout budget de la catégorie : par défaut, propres à un mois et report.
export function removeBudget(s: BudgetStore, category: Category) {
  updateCategory(s, category.id, "Retirer le budget",
    c => ({ ...c, monthlyBudgetCents: null, budgetOverridesCents: null, budgetRollover: null }));
}

/// Active ou coupe le report du reste / dépassement d'un mois sur l'autre.
export function setBudgetRollover(s: BudgetStore, enabled: boolean, category: Category) {
  updateCategory(s, category.id, enabled ? "Activer le report" : "Désactiver le report",
    c => ({ ...c, budgetRollover: enabled ? true : null }));
}

/// Objectif d'épargne et revenus prévus.
export function setBudgetPlan(s: BudgetStore, plan: { savingsGoalCents: number | null; expectedIncomeCents: number | null }) {
  if (plan.savingsGoalCents === s.budgetPlan.savingsGoalCents && plan.expectedIncomeCents === s.budgetPlan.expectedIncomeCents) return;
  s.registerUndo("Modifier la planification");
  s.budgetPlan = { savingsGoalCents: plan.savingsGoalCents, expectedIncomeCents: plan.expectedIncomeCents };
  s.saveSettings();
}
