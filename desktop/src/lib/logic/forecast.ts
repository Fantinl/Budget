// Prévision de fin de mois. Port de BudgetStore+Forecast.swift. Montants en centimes.
import { type Account, isEarning, isSpending, newID } from "../model";
import { addDays, addMonths, daysInMonth, isInMonth, startOfDay, startOfMonth } from "../dates";
import type { BudgetStore } from "../store.svelte";
import { occurrences, signedRecurring } from "./recurring";
import { balance } from "./accounts";
import { daysRemaining } from "./budgets";

/// Une récurrente à venir.
export interface UpcomingRecurring { id: string; name: string; date: Date; /** signé */ amountCents: number }

/// Prévision du solde du mois en fin de mois.
export interface MonthForecast {
  /// Revenus − dépenses du mois à ce jour (hors virements).
  currentCents: number;
  /// Récurrentes actives à venir (de demain à la fin du mois), triées par date.
  upcoming: UpcomingRecurring[];
  /// Dépenses courantes restantes estimées (positif), null si historique insuffisant.
  estimatedSpendingCents: number | null;
  /// Moyenne journalière utilisée pour l'estimation.
  dailyAverageCents: number | null;
  upcomingTotalCents: number;
  projectedCents: number;
}

/// Récurrentes actives à venir (demain → fin du mois), éventuellement pour un seul compte.
export function upcomingRecurring(s: BudgetStore, now: Date = new Date(), accountID: string | null = null): UpcomingRecurring[] {
  const tomorrow = addDays(startOfDay(now), 1);
  const lastDay = addDays(addMonths(startOfMonth(now), 1), -1);
  if (tomorrow.getTime() > lastDay.getTime()) return [];
  const result: UpcomingRecurring[] = [];
  for (const operation of s.recurringOperations) {
    if (!operation.isActive) continue;
    const resolved = operation.accountID ?? s.defaultAccount.id;
    if (accountID !== null && resolved !== accountID) continue;
    const signed = signedRecurring(operation);
    for (const date of occurrences(operation, tomorrow, lastDay)) {
      result.push({ id: newID(), name: operation.name, date, amountCents: signed });
    }
  }
  return result.sort((a, b) => a.date.getTime() - b.date.getTime());
}

/// Prévision de fin de mois pour le mois en cours (tous comptes).
export function monthForecast(s: BudgetStore, now: Date = new Date()): MonthForecast {
  let current = 0;
  for (const t of s.transactions) {
    if (!isInMonth(t.date, now)) continue;
    if (isSpending(t)) current -= t.amountCents;
    else if (isEarning(t)) current += t.amountCents;
  }

  // Moyenne journalière des dépenses non récurrentes des 3 mois précédents.
  // Il faut au moins 2 de ces mois avec des dépenses, sinon pas d'estimation.
  const monthStart = startOfMonth(now);
  let days = 0;
  let total = 0;
  let monthsWithSpending = 0;
  for (let back = 1; back <= 3; back++) {
    const month = addMonths(monthStart, -back);
    let sum = 0;
    let any = false;
    for (const t of s.transactions) {
      if (isSpending(t) && t.recurringID === null && isInMonth(t.date, month)) { any = true; sum += t.amountCents; }
    }
    if (!any) continue;
    monthsWithSpending += 1;
    total += sum;
    days += daysInMonth(month);
  }
  let estimate: number | null = null;
  let average: number | null = null;
  if (monthsWithSpending >= 2 && days > 0) {
    const daily = total / days;
    average = daily;
    estimate = Math.max(0, daily * (daysRemaining(now, now) - 1));
  }
  const upcoming = upcomingRecurring(s, now);
  const upcomingTotal = upcoming.reduce((n, u) => n + u.amountCents, 0);
  return { currentCents: current, upcoming, estimatedSpendingCents: estimate, dailyAverageCents: average,
           upcomingTotalCents: upcomingTotal, projectedCents: current + upcomingTotal - (estimate ?? 0) };
}

/// Solde prévu en fin de mois d'un compte (null = compte par défaut) : solde actuel + récurrentes à venir.
export function projectedBalance(s: BudgetStore, account: Account | null = null, now: Date = new Date()): number {
  const target = account ?? s.defaultAccount;
  const upcoming = upcomingRecurring(s, now, target.id).reduce((n, u) => n + u.amountCents, 0);
  return balance(s, target) + upcoming;
}
