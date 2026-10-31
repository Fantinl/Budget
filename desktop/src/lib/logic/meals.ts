// Repas Izly : décompte automatique d'un repas par jour choisi, revue hebdomadaire et ajout en masse.
// Port de BudgetStore+Meals.swift.

import {
  type Account, DEFAULT_MEAL_PRICE_CENTS, fallbackCategoryID, type MealPlan, resolvedAccountID, type Transaction,
} from "../model";
import { addDays, daysBetween, startOfDay, weekday } from "../dates";
import { BudgetStore } from "../store.svelte";
import { balance } from "./accounts";
import { sha1, toHex } from "./sha1";

/// Garde-fou : nombre maximal de repas créés par appel.
const MAX_MEALS_PER_CALL = 400;
/// Nombre de jours après lequel la revue est proposée.
export const MEAL_REVIEW_DELAY = 7;
/// Nombre maximal de jours affichés dans la revue.
export const MEAL_REVIEW_SPAN = 14;

// MARK: - Identifiant fixe

/// Identifiant fixe d'un repas automatique (compte + jour) : le Mac et le Windows (et l'iPhone) créent le même
/// enregistrement pour un même jour, que la synchronisation fusionne au lieu de le dupliquer.
/// UUID « version 5 » dérivé de SHA-1 de « meal:<compte>:<année>-<mois>-<jour> » (sans zéros de remplissage), en majuscules.
export function mealID(accountID: string, day: Date): string {
  const key = `meal:${accountID}:${day.getFullYear()}-${day.getMonth() + 1}-${day.getDate()}`;
  const bytes = sha1(new TextEncoder().encode(key)).slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const h = toHex(bytes);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`.toUpperCase();
}

// MARK: - Génération automatique

/// Catégorie demandée si elle existe, sinon « Autre ».
function mealCategoryID(s: BudgetStore, requested: string): string {
  return s.categories.some(c => c.id === requested) ? requested : fallbackCategoryID("expense");
}

/// Débuts de jour (en millisecondes) où le compte a déjà un repas automatique.
function mealDays(s: BudgetStore, accountID: string): Set<number> {
  const days = new Set<number>();
  for (const t of s.transactions) {
    if (t.isAutoMeal === true && resolvedAccountID(t) === accountID) days.add(startOfDay(t.date).getTime());
  }
  return days;
}

function makeMeal(day: Date, priceCents: number, categoryID: string, accountID: string): Transaction {
  return {
    id: mealID(accountID, day), amountCents: priceCents, kind: "expense", categoryID, note: "Repas Crous",
    date: new Date(day.getFullYear(), day.getMonth(), day.getDate(), 12, 0, 0), accountID: BudgetStore.storedAccountID(accountID),
    recurringID: null, transferID: null, tagIDs: null, isAutoMeal: true,
  };
}

/// Repas à créer sur la période ; renvoie aussi le dernier jour parcouru (pour reprendre après le garde-fou).
function mealsFor(
  accountID: string, weekdays: readonly number[], priceCents: number, from: Date, to: Date, taken: Set<number>,
  limit: number, categoryID: string,
): { meals: Transaction[]; lastDay: Date | null } {
  const meals: Transaction[] = [];
  let day = from;
  let lastDay: Date | null = null;
  while (day.getTime() <= to.getTime()) {
    if (meals.length >= limit) break;
    lastDay = day;
    if (weekdays.includes(weekday(day)) && !taken.has(day.getTime())) {
      meals.push(makeMeal(day, priceCents, categoryID, accountID));
    }
    day = addDays(day, 1);
  }
  return { meals, lastDay };
}

/// Crée les repas des jours passés (jusqu'à aujourd'hui inclus) non encore décomptés. Appelée au lancement.
export function generateDueMeals(s: BudgetStore, now: Date = new Date()): void {
  const today = startOfDay(now);
  const created: Transaction[] = [];
  const accounts = [...s.accounts];
  let changed = false;

  for (let index = 0; index < accounts.length; index++) {
    const account = accounts[index];
    const plan = account.mealPlan;
    if (account.kind !== "izly" || account.isArchived || !plan || !plan.isEnabled) continue;
    let from = startOfDay(plan.startDate);
    if (plan.lastGeneratedDate) {
      const next = addDays(startOfDay(plan.lastGeneratedDate), 1);
      if (next.getTime() > from.getTime()) from = next;
    }
    if (from.getTime() > today.getTime()) continue;

    const taken = mealDays(s, account.id);
    const budget = MAX_MEALS_PER_CALL - created.length;
    if (budget <= 0) break;
    const { meals, lastDay } = mealsFor(account.id, plan.weekdays, plan.priceCents, from, today, taken, budget,
                                        mealCategoryID(s, plan.categoryID));
    created.push(...meals);
    if (lastDay && lastDay.getTime() !== plan.lastGeneratedDate?.getTime()) {
      accounts[index] = { ...account, mealPlan: { ...plan, lastGeneratedDate: lastDay } };
      changed = true;
    }
  }

  if (changed) s.accounts = accounts;
  if (created.length > 0) {
    s.transactions = [...s.transactions, ...created];
    s.saveTransactions();
  }
  if (changed) s.saveSettings();
}

/// Supprime les repas automatiques en double (même compte, même jour), créés par deux appareils avant les identifiants
/// fixes. Le choix est le même sur chaque appareil : on garde l'identifiant fixe s'il est là, sinon le plus petit.
/// Renvoie vrai si quelque chose a été supprimé.
export function removeDuplicateAutoMeals(s: BudgetStore): boolean {
  const groups = new Map<string, Transaction[]>();
  for (const t of s.transactions) {
    if (t.isAutoMeal !== true) continue;
    const key = `${resolvedAccountID(t)}|${startOfDay(t.date).getTime()}`;
    groups.set(key, [...(groups.get(key) ?? []), t]);
  }
  const duplicates = new Set<string>();
  for (const group of groups.values()) {
    if (group.length < 2) continue;
    const fixed = mealID(resolvedAccountID(group[0]), group[0].date);
    const keep = group.find(t => t.id === fixed)?.id ?? group.map(t => t.id).reduce((a, b) => (b < a ? b : a));
    for (const t of group) if (t.id !== keep) duplicates.add(t.id);
  }
  if (duplicates.size === 0) return false;
  s.transactions = s.transactions.filter(t => !duplicates.has(t.id));
  s.saveTransactions();
  return true;
}

// MARK: - Lecture

/// Repas automatiques du compte sur l'intervalle [start, end] (bornes incluses comme `DateInterval`), du plus ancien au plus récent.
export function mealsOf(s: BudgetStore, account: Account, interval: { start: Date; end: Date }): Transaction[] {
  return s.transactions
    .filter(t => t.isAutoMeal === true && resolvedAccountID(t) === account.id
      && t.date.getTime() >= interval.start.getTime() && t.date.getTime() <= interval.end.getTime())
    .sort((a, b) => a.date.getTime() - b.date.getTime());
}

/// Nombre de repas que permet le solde actuel (0 si prix nul ou solde négatif).
export function mealsRemaining(s: BudgetStore, account: Account): number {
  const price = account.mealPlan?.priceCents ?? DEFAULT_MEAL_PRICE_CENTS;
  const bal = balance(s, account);
  if (price <= 0 || bal <= 0) return 0;
  return Math.floor(bal / price);
}

// MARK: - Ajout / suppression en masse

/// Ajoute un repas par jour de `weekdays` entre `from` et `to` (inclus), en sautant les jours déjà décomptés.
export function addMeals(s: BudgetStore, account: Account, from: Date, to: Date, weekdays: readonly number[], priceCents: number): number {
  const start = startOfDay(from);
  const end = startOfDay(to);
  if (start.getTime() > end.getTime() || priceCents <= 0 || weekdays.length === 0) return 0;
  const { meals } = mealsFor(account.id, weekdays, priceCents, start, end, mealDays(s, account.id), MAX_MEALS_PER_CALL,
                             mealCategoryID(s, account.mealPlan?.categoryID ?? "restaurants"));
  if (meals.length === 0) return 0;
  s.registerUndo("Ajouter des repas");
  s.transactions = [...s.transactions, ...meals];
  s.saveTransactions();
  return meals.length;
}

/// Nombre de repas qu'ajouterait `addMeals` (aperçu).
export function mealsToAdd(s: BudgetStore, account: Account, from: Date, to: Date, weekdays: readonly number[]): number {
  const taken = mealDays(s, account.id);
  let day = startOfDay(from);
  const end = startOfDay(to);
  let count = 0;
  while (day.getTime() <= end.getTime() && count < MAX_MEALS_PER_CALL) {
    if (weekdays.includes(weekday(day)) && !taken.has(day.getTime())) count++;
    day = addDays(day, 1);
  }
  return count;
}

/// Supprime des repas (annulable).
export function removeMeals(s: BudgetStore, ids: ReadonlySet<string>): number {
  const count = s.transactions.filter(t => ids.has(t.id) && t.isAutoMeal === true).length;
  if (count === 0) return 0;
  s.registerUndo("Supprimer des repas");
  s.transactions = s.transactions.filter(t => !(ids.has(t.id) && t.isAutoMeal === true));
  s.saveTransactions();
  return count;
}

// MARK: - Revue hebdomadaire

/// Premier jour de la période non revue.
function reviewStart(plan: MealPlan): Date {
  const start = startOfDay(plan.startDate);
  if (!plan.lastReviewDate) return start;
  const next = addDays(startOfDay(plan.lastReviewDate), 1);
  return next.getTime() > start.getTime() ? next : start;
}

/// Compte Izly à revoir : plan actif, dernière revue (ou début) d'au moins 7 jours, repas à vérifier.
export function needsMealReview(s: BudgetStore, now: Date = new Date()): Account | null {
  const today = startOfDay(now);
  return s.activeAccounts.find(account => {
    const plan = account.mealPlan;
    if (account.kind !== "izly" || !plan || !plan.isEnabled) return false;
    const reference = startOfDay(plan.lastReviewDate ?? plan.startDate);
    if (daysBetween(reference, today) < MEAL_REVIEW_DELAY) return false;
    const from = reviewStart(plan);
    const end = addDays(today, 1);
    return mealsOf(s, account, { start: from, end: end.getTime() > from.getTime() ? end : from }).length > 0;
  }) ?? null;
}

/// Note que la période jusqu'à aujourd'hui a été revue.
export function markMealsReviewed(s: BudgetStore, account: Account, now: Date = new Date()): void {
  const index = s.accounts.findIndex(a => a.id === account.id);
  const plan = index >= 0 ? s.accounts[index].mealPlan : null;
  if (index < 0 || !plan) return;
  s.accounts = s.accounts.with(index, { ...s.accounts[index], mealPlan: { ...plan, lastReviewDate: startOfDay(now) } });
  s.saveSettings();
}

/// Jours proposés à la revue (au plus 14, du plus ancien au plus récent) : jours du plan et jours avec repas.
export function mealReviewDays(s: BudgetStore, account: Account, now: Date = new Date()): Date[] {
  const plan = account.mealPlan;
  if (!plan) return [];
  const today = startOfDay(now);
  let from = reviewStart(plan);
  const limit = addDays(today, -(MEAL_REVIEW_SPAN - 1));
  if (limit.getTime() > from.getTime()) from = limit;
  const withMeal = mealDays(s, account.id);
  const result: Date[] = [];
  for (let day = from; day.getTime() <= today.getTime(); day = addDays(day, 1)) {
    if (plan.weekdays.includes(weekday(day)) || withMeal.has(day.getTime())) result.push(day);
  }
  return result;
}

/// Applique la revue en une seule annulation : `present` = jours où l'on a mangé parmi `days`.
export function applyMealReview(s: BudgetStore, account: Account, days: Date[], present: Date[], now: Date = new Date()): void {
  const plan = account.mealPlan;
  const priceCents = plan?.priceCents ?? DEFAULT_MEAL_PRICE_CENTS;
  const category = mealCategoryID(s, plan?.categoryID ?? "restaurants");
  const daySet = new Set(days.map(d => startOfDay(d).getTime()));
  const wanted = new Set(present.map(d => startOfDay(d).getTime()));
  const existing = s.transactions.filter(t => t.isAutoMeal === true && resolvedAccountID(t) === account.id
    && daySet.has(startOfDay(t.date).getTime()));
  const have = new Set(existing.map(t => startOfDay(t.date).getTime()));
  const doomed = new Set(existing.filter(t => !wanted.has(startOfDay(t.date).getTime())).map(t => t.id));
  const added = [...daySet].filter(d => wanted.has(d) && !have.has(d)).sort((a, b) => a - b)
    .map(d => makeMeal(new Date(d), priceCents, category, account.id));
  s.registerUndo("Revue des repas");
  if (doomed.size > 0 || added.length > 0) {
    s.transactions = [...s.transactions.filter(t => !doomed.has(t.id)), ...added];
    s.saveTransactions();
  }
  markMealsReviewed(s, account, now);
}

// MARK: - Opérations Izly masquées

/// Les opérations d'un compte Izly n'apparaissent pas individuellement dans l'écran Opérations
/// (elles restent dans le compte, le résumé du mois, les budgets et les statistiques).
export function isHiddenFromOperations(s: BudgetStore, t: Transaction): boolean {
  return s.accounts.find(a => a.id === resolvedAccountID(t))?.kind === "izly";
}

/// Dépenses Izly du mois (pour la ligne récapitulative) : nombre et total en centimes.
export function izlySpending(s: BudgetStore, transactions: Transaction[]): { count: number; totalCents: number } {
  const spending = transactions.filter(t => isHiddenFromOperations(s, t) && t.kind === "expense" && t.transferID === null);
  return { count: spending.length, totalCents: spending.reduce((sum, t) => sum + t.amountCents, 0) };
}

/// Lit un prix saisi (« 1 », « 1,50 ») en centimes ; null si vide, invalide ou ≤ 0.
export function parseMealPrice(text: string): number | null {
  const cleaned = text.replace(/,/g, ".").replace(/\s/g, "");
  if (!/^[+-]?(\d+\.?\d*|\.\d+)$/.test(cleaned)) return null;
  const value = Number(cleaned);
  return value > 0 ? Math.round(value * 100) : null;
}
