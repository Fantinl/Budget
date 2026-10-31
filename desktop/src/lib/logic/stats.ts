// Calcul des statistiques (sans interface). Port de Stats.swift. Montants en centimes.
import { type Category, isEarning, isSpending, isTransfer, type Transaction } from "../model";
import { addMonths, startOfMonth, startOfYear } from "../dates";

export type StatsPeriod = "month" | "threeMonths" | "year" | "all";
export const statsPeriods: StatsPeriod[] = ["month", "threeMonths", "year", "all"];
export const statsPeriodLabel: Record<StatsPeriod, string> = { month: "Mois", threeMonths: "3 mois", year: "Année", all: "Tout" };
/// Mois et année se parcourent avec précédent / suivant.
export const isNavigable = (p: StatsPeriod) => p === "month" || p === "year";
/// Nombre de mois d'une période fixe (null pour « Tout »).
export const monthSpan = (p: StatsPeriod): number | null => ({ month: 1, threeMonths: 3, year: 12, all: null } as const)[p];

export interface CategoryTotal { category: Category; amountCents: number; share: number; id: string }
export interface MonthCategoryAmount { month: Date; category: Category; amountCents: number; id: string }
export interface MonthIncome { month: Date; amountCents: number }

export interface StatsSnapshot {
  /// Inclus
  start: Date;
  /// Exclu
  end: Date;
  expensesCents: number;
  incomeCents: number;
  averagePerMonthCents: number;
  /// Variation des dépenses vs période précédente (0.12 = +12 %), null si pas de référence.
  expenseChange: number | null;
  categories: CategoryTotal[];
  months: Date[];
  monthlyExpenses: MonthCategoryAmount[];
  monthlyIncome: MonthIncome[];
  topExpenses: Transaction[];
  hasData: boolean;
  balanceCents: number;
}

const inRange = (t: Transaction, from: Date, to: Date) => t.date.getTime() >= from.getTime() && t.date.getTime() < to.getTime();
const monthIndex = (d: Date) => d.getFullYear() * 12 + d.getMonth();

export function makeStatsSnapshot(transactions: readonly Transaction[], period: StatsPeriod, offset: number,
                                  category: (id: string) => Category, now: Date = new Date()): StatsSnapshot {
  const currentMonth = startOfMonth(now);

  // Bornes de la période
  let s: Date;
  let e: Date;
  switch (period) {
    case "month":
      s = addMonths(currentMonth, offset);
      e = addMonths(s, 1);
      break;
    case "threeMonths":
      e = addMonths(currentMonth, 1);
      s = addMonths(e, -3);
      break;
    case "year":
      s = addMonths(startOfYear(now), 12 * offset);
      e = addMonths(s, 12);
      break;
    case "all": {
      let min = Infinity, max = -Infinity;
      for (const t of transactions) { const x = t.date.getTime(); if (x < min) min = x; if (x > max) max = x; }
      const first = min === Infinity ? currentMonth : startOfMonth(new Date(min));
      const last = max === -Infinity ? currentMonth : startOfMonth(new Date(max));
      s = first.getTime() < currentMonth.getTime() ? first : currentMonth;
      e = addMonths(last.getTime() > currentMonth.getTime() ? last : currentMonth, 1);
      break;
    }
  }

  // Une seule passe sur les opérations de la période
  const current: Transaction[] = [];
  const spent: Transaction[] = [];
  let expenses = 0;
  let income = 0;
  for (const t of transactions) {
    if (!inRange(t, s, e)) continue;
    current.push(t);
    if (isSpending(t)) { spent.push(t); expenses += t.amountCents; }
    else if (isEarning(t)) income += t.amountCents;
  }

  // Moyenne : on ne compte pas les mois futurs
  const nextMonth = addMonths(currentMonth, 1);
  const elapsedEnd = e.getTime() < nextMonth.getTime() ? e : nextMonth;
  const elapsed = (elapsedEnd.getFullYear() - s.getFullYear()) * 12 + (elapsedEnd.getMonth() - s.getMonth());
  const averagePerMonth = expenses / Math.max(1, elapsed);

  // Période précédente, à date équivalente : si la période est en cours (ex. 1er–16 octobre),
  // on la compare au même nombre de jours de la précédente (1er–16 septembre).
  let expenseChange: number | null = null;
  const span = monthSpan(period);
  if (span !== null) {
    const cutoff = e.getTime() < now.getTime() ? e : now;
    const prevEnd = addMonths(cutoff, -span);
    const prevStart = addMonths(s, -span);
    let prev = 0;
    for (const t of transactions) if (isSpending(t) && inRange(t, prevStart, prevEnd)) prev += t.amountCents;
    expenseChange = prev > 0 ? (expenses - prev) / prev : null;
  }

  // Répartition par catégorie
  const byCategory = new Map<string, number>();
  for (const t of spent) byCategory.set(t.categoryID, (byCategory.get(t.categoryID) ?? 0) + t.amountCents);
  const categories = [...byCategory]
    .map(([id, amount]) => ({ category: category(id), amountCents: amount, share: expenses > 0 ? amount / expenses : 0, id }))
    .sort((a, b) => b.amountCents - a.amountCents);

  // Évolution mensuelle : 12 mois minimum, se terminant à la fin de la période
  const lastMonth = addMonths(e, -1);
  const back11 = addMonths(lastMonth, -11);
  const firstMonth = s.getTime() < back11.getTime() ? s : back11;
  const months: Date[] = [];
  for (let m = firstMonth; m.getTime() <= lastMonth.getTime(); m = addMonths(m, 1)) months.push(m);

  const chartEnd = addMonths(lastMonth, 1);
  const expenseBuckets = new Map<number, Map<string, number>>();
  const incomeBuckets = new Map<number, number>();
  for (const t of transactions) {
    if (!inRange(t, firstMonth, chartEnd) || isTransfer(t)) continue;
    const key = monthIndex(t.date);
    if (t.kind === "expense") {
      let bucket = expenseBuckets.get(key);
      if (!bucket) { bucket = new Map(); expenseBuckets.set(key, bucket); }
      bucket.set(t.categoryID, (bucket.get(t.categoryID) ?? 0) + t.amountCents);
    } else {
      incomeBuckets.set(key, (incomeBuckets.get(key) ?? 0) + t.amountCents);
    }
  }
  const monthlyExpenses: MonthCategoryAmount[] = [];
  for (const month of months) {
    const bucket = expenseBuckets.get(monthIndex(month));
    if (!bucket) continue;
    for (const [id, amount] of [...bucket].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))) {
      monthlyExpenses.push({ month, category: category(id), amountCents: amount, id: `${month.getTime()}-${id}` });
    }
  }
  const monthlyIncome = months.map(month => ({ month, amountCents: incomeBuckets.get(monthIndex(month)) ?? 0 }));

  return {
    start: s, end: e, expensesCents: expenses, incomeCents: income, averagePerMonthCents: averagePerMonth, expenseChange,
    categories, months, monthlyExpenses, monthlyIncome,
    topExpenses: [...spent].sort((a, b) => b.amountCents - a.amountCents).slice(0, 5),
    hasData: current.length > 0, balanceCents: income - expenses,
  };
}

/// Dépenses (hors virements) d'une catégorie sur [start, end[, de la plus récente à la plus ancienne.
export function categoryTransactions(categoryID: string, transactions: readonly Transaction[], start: Date, end: Date): Transaction[] {
  return transactions
    .filter(t => isSpending(t) && t.categoryID === categoryID && inRange(t, start, end))
    .sort((a, b) => b.date.getTime() - a.date.getTime());
}

/// Débuts de mois ayant au moins une opération (points du sélecteur de période), sans doublon.
export function monthStartsWithData(transactions: readonly Transaction[]): Date[] {
  const seen = new Map<number, Date>();
  for (const t of transactions) {
    const key = t.date.getFullYear() * 12 + t.date.getMonth();
    if (!seen.has(key)) seen.set(key, new Date(t.date.getFullYear(), t.date.getMonth(), 1));
  }
  return [...seen.values()];
}
