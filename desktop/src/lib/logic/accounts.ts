// Comptes : soldes et valeurs. Port de BudgetStore+Accounts.swift (partie calcul ; les modifications
// — upsert, archive, suppression, ordre, compte par défaut — s'ajoutent dans ce même fichier).

import {
  type Account, type AccountFamily, type AccountKind, defaultMealPlan, hasMarketValue, kindsInFamily, MAIN_ACCOUNT_ID,
  newAccount, resolvedAccountID, signedCents, type Transaction,
} from "../model";
import { isToday } from "../dates";
import type { BudgetStore } from "../store.svelte";

/// Opérations d'un compte (toutes dates), de la plus récente à la plus ancienne.
export function transactionsOf(s: BudgetStore, account: Account): Transaction[] {
  return s.transactions.filter(t => resolvedAccountID(t) === account.id).sort((a, b) => b.date.getTime() - a.date.getTime());
}

/// Nombre d'opérations rattachées au compte.
export function accountUsageCount(s: BudgetStore, account: Account): number {
  let n = 0;
  for (const t of s.transactions) if (resolvedAccountID(t) === account.id) n++;
  return n;
}

/// Solde initial + revenus − dépenses du compte jusqu'à la date (incluse).
export function balance(s: BudgetStore, account: Account, asOf: Date = new Date()): number {
  const limit = asOf.getTime();
  let total = account.initialBalanceCents;
  for (const t of s.transactions) {
    if (resolvedAccountID(t) === account.id && t.date.getTime() <= limit) total += signedCents(t);
  }
  return total;
}

/// Valeur du compte : valorisation saisie pour un placement, sinon le solde.
export function value(s: BudgetStore, account: Account): number {
  return hasMarketValue(account.kind) ? (account.marketValueCents ?? balance(s, account)) : balance(s, account);
}

/// Plus ou moins-value d'un placement (valorisation − versements), null sans valorisation.
export function gain(s: BudgetStore, account: Account): number | null {
  if (!hasMarketValue(account.kind) || account.marketValueCents === null) return null;
  return account.marketValueCents - balance(s, account);
}

/// Somme des valeurs des comptes non archivés (patrimoine).
export function totalBalance(s: BudgetStore, asOf: Date = new Date()): number {
  const today = isToday(asOf);
  return s.activeAccounts.reduce((sum, a) => sum + (today ? value(s, a) : balance(s, a, asOf)), 0);
}

/// Banques déjà saisies (suggestions et regroupement), triées.
export function banks(s: BudgetStore): string[] {
  const set = new Set(s.accounts.map(a => a.bank?.trim() ?? "").filter(b => b.length > 0));
  return [...set].sort((a, b) => a.localeCompare(b, "fr", { numeric: true, sensitivity: "base" }));
}

// MARK: - Modifications

/// Compte par défaut des nouvelles opérations.
export function setDefaultAccount(s: BudgetStore, account: Account) {
  s.registerUndo("Changer le compte par défaut");
  s.defaultAccountID = account.id;
  s.saveSettings();
}

export function upsertAccount(s: BudgetStore, account: Account) {
  s.registerUndo("Modifier le compte");
  // Le compte principal ne peut pas être archivé.
  const next = account.id === MAIN_ACCOUNT_ID ? { ...account, isArchived: false } : account;
  const index = s.accounts.findIndex(a => a.id === next.id);
  s.accounts = index >= 0 ? s.accounts.with(index, next) : [...s.accounts, next];
  s.saveSettings();
}

export function archiveAccount(s: BudgetStore, account: Account) {
  s.registerUndo("Archiver le compte");
  setArchived(s, account, true);
}

export function unarchiveAccount(s: BudgetStore, account: Account) {
  s.registerUndo("Désarchiver le compte");
  setArchived(s, account, false);
}

function setArchived(s: BudgetStore, account: Account, archived: boolean) {
  const index = s.accounts.findIndex(a => a.id === account.id);
  if (account.id === MAIN_ACCOUNT_ID || index < 0) return;
  s.accounts = s.accounts.with(index, { ...s.accounts[index], isArchived: archived });
  s.saveSettings();
}

/// Supprime un compte sans opération (ni le compte principal). Renvoie false si refusé.
export function deleteAccount(s: BudgetStore, account: Account): boolean {
  s.registerUndo("Supprimer le compte");
  if (account.id === MAIN_ACCOUNT_ID || accountUsageCount(s, account) !== 0) return false;
  s.accounts = s.accounts.filter(a => a.id !== account.id);
  s.saveSettings();
  return true;
}

/// Comme `Array.move(fromOffsets:toOffset:)` de SwiftUI : `destination` est un indice d'insertion dans la liste d'origine.
export function moveItems<T>(items: readonly T[], source: number[], destination: number): T[] {
  const moving = [...new Set(source)].filter(i => i >= 0 && i < items.length).sort((a, b) => a - b);
  const insertAt = destination - moving.filter(i => i < destination).length;
  const rest = items.filter((_, i) => !moving.includes(i));
  rest.splice(insertAt, 0, ...moving.map(i => items[i]));
  return rest;
}

export function moveAccounts(s: BudgetStore, source: number[], destination: number) {
  s.registerUndo("Réordonner les comptes");
  s.accounts = moveItems(s.accounts, source, destination);
  s.saveSettings();
}

// MARK: - Types de compte (profil étudiant)

/// Types sans banque associée (espèces, Izly).
export const hidesBank = (kind: AccountKind) => kind === "cash" || kind === "izly";

/// Types proposables dans une famille : Izly seulement pour un étudiant (ou si déjà utilisé).
export function selectableKinds(family: AccountFamily, studentEnabled: boolean, current: AccountKind | null = null): AccountKind[] {
  return kindsInFamily(family).filter(k => k !== "izly" || studentEnabled || current === "izly");
}

/// Compte Izly neuf, sur la première couleur de palette non utilisée (repas automatiques activés).
export function makeIzly(existing: Account[], paletteCount: number, options: { id?: string; balanceCents?: number } = {}): Account {
  const count = Math.max(paletteCount, 1);
  const used = new Set(existing.map(a => a.colorIndex));
  let color = existing.length % count;
  for (let i = 0; i < count; i++) if (!used.has(i)) { color = i; break; }
  return newAccount({ ...(options.id ? { id: options.id } : {}), name: "Izly", kind: "izly", colorIndex: color,
                      initialBalanceCents: options.balanceCents ?? 0, mealPlan: defaultMealPlan() });
}
