// Éléments de l'assistant de démarrage : récurrentes et ajouts rapides proposés (OnboardingRecurring.swift,
// OnboardingQuick.swift, OnboardingComponents.swift).

import { DEFAULT_MEAL_PRICE_CENTS, type Kind, type QuickExpense, newID } from "../../lib/model";
import { addDays, addMonths, daysInMonth, startOfDay, startOfMonth } from "../../lib/dates";
import type { BudgetStore } from "../../lib/store.svelte";
import { parseDecimal } from "../accounts/accountDraft";

const plainNumber = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2, useGrouping: false });

/// Montant éditable (« 2,5 ») à partir de centimes.
export const amountText = (cents: number) => plainNumber.format(cents / 100);

/// Montant strictement positif en centimes, null sinon.
export function positiveCents(text: string): number | null {
  const value = parseDecimal(text);
  if (value === null) return null;
  const cents = Math.round(value * 100);
  return cents > 0 ? cents : null;
}

/// Texte pluriel simple : « 2 comptes ».
export const count = (n: number, singular: string, plural: string) => `${n} ${n > 1 ? plural : singular}`;

// MARK: - Récurrentes

export interface RecurringItem {
  id: string;
  name: string;
  categoryID: string;
  kind: Kind;
  amountText: string;
  dayText: string;
  selected: boolean;
  isCustom: boolean;
}

function recurringItem(name: string, categoryID: string, amountCents: number, day: number, kind: Kind = "expense", isCustom = false): RecurringItem {
  return { id: newID(), name, categoryID, kind, amountText: amountText(amountCents), dayText: String(day), selected: isCustom, isCustom };
}

export const recurringSuggestions = (): RecurringItem[] => [
  recurringItem("Loyer", "housing", 80000, 5),
  recurringItem("Salaire", "salary", 200000, 28, "income"),
  recurringItem("Électricité", "housing", 6000, 10),
  recurringItem("Internet / box", "housing", 3000, 12),
  recurringItem("Forfait mobile", "subscriptions", 1500, 15),
  recurringItem("Assurance habitation", "housing", 2000, 8),
  recurringItem("Netflix / Spotify", "subscriptions", 1000, 15),
  recurringItem("Transport (pass Navigo)", "transport", 9080, 1),
];

/// Récurrente personnalisée ajoutée par « Ajouter une opération ».
export function customRecurring(categoryID: string): RecurringItem {
  const item = recurringItem("", categoryID, 0, 1, "expense", true);
  item.amountText = "";
  return item;
}

export const itemAmount = (i: { amountText: string }) => positiveCents(i.amountText);
export function itemDay(i: RecurringItem): number | null {
  const t = i.dayText.trim();
  if (!/^[+-]?\d+$/.test(t)) return null;
  const n = Number(t);
  return n >= 1 && n <= 31 ? n : null;
}
export const recurringValid = (i: RecurringItem) => i.name.trim() !== "" && itemAmount(i) !== null && itemDay(i) !== null;

/// Première date (aujourd'hui ou plus tard) tombant le jour choisi ; pas d'échéance passée.
export function nextDate(day: number, now: Date = new Date()): Date {
  const today = startOfDay(now);
  const month = startOfMonth(today);
  let fallback = today;
  for (let offset = 0; offset < 14; offset++) {
    const target = addMonths(month, offset);
    const length = daysInMonth(target);
    const date = addDays(target, Math.min(day, length) - 1);
    if (date < today) continue;
    if (length >= day) return date;
    if (fallback === today) fallback = date;
  }
  return fallback;
}

// MARK: - Ajouts rapides

export interface QuickItem {
  id: string;
  /// Ajout rapide existant, conservé tel quel (hors montant).
  existing: QuickExpense | null;
  name: string;
  categoryID: string;
  amountText: string;
  selected: boolean;
  /// Suggestion « Repas Crous » (débitée sur le compte Izly).
  isCrous: boolean;
  accountID: string | null;
}

function quickItem(name: string, categoryID: string, amountCents: number): QuickItem {
  return { id: newID(), existing: null, name, categoryID, amountText: amountText(amountCents), selected: false, isCrous: false, accountID: null };
}

export const existingQuickItem = (q: QuickExpense): QuickItem =>
  ({ id: newID(), existing: q, name: q.name, categoryID: q.categoryID, amountText: amountText(q.amountCents), selected: true, isCrous: false, accountID: null });

/// Repas Crous à 1 €, coché par défaut.
export function crousItem(categoryID: string): QuickItem {
  return { ...quickItem("Repas Crous", categoryID, DEFAULT_MEAL_PRICE_CENTS), isCrous: true, selected: true };
}

export const quickSuggestions = (): QuickItem[] => [
  quickItem("Café", "restaurants", 250),
  quickItem("Boulangerie", "groceries", 300),
  quickItem("Déjeuner", "restaurants", 1200),
  quickItem("Essence", "transport", 6000),
  quickItem("Courses", "groceries", 5000),
  quickItem("Tabac / presse", "shopping", 500),
  quickItem("Parking", "transport", 300),
];

export const quickValid = (i: QuickItem) => !i.selected || itemAmount(i) !== null;

export function toQuickExpense(item: QuickItem, s: BudgetStore): QuickExpense | null {
  const amount = itemAmount(item);
  if (!item.selected || amount === null) return null;
  if (item.existing) return { ...item.existing, amountCents: amount };
  const known = s.categories.some(c => c.id === item.categoryID && !c.isHidden && c.kind === "expense");
  return { id: newID(), name: item.name, amountCents: amount, kind: "expense",
           categoryID: known ? item.categoryID : s.fallbackCategory("expense").id, note: "", accountID: item.accountID };
}

/// Banques proposées en pastilles (AccountEditorSheet.commonBanks).
export const commonBanks = [
  "BNP Paribas", "Société Générale", "Crédit Agricole", "Crédit Mutuel", "LCL", "La Banque Postale",
  "Caisse d'Épargne", "Banque Populaire", "Boursorama", "Fortuneo", "Hello bank!", "Revolut", "N26", "Trade Republic",
];
