// Filtres de la liste des opérations et recherche. Port de FilterModel.swift (partie logique) et de la
// recherche de ContentView.swift. Les filtres n'affectent pas le résumé du mois.

import { type Transaction, isEarning, isSpending, isTransfer, resolvedAccountID } from "../model";
import type { BudgetStore } from "../store.svelte";

export type FilterKind = "all" | "expense" | "income" | "transfer";
export const filterKinds: FilterKind[] = ["all", "expense", "income", "transfer"];
export const filterKindLabel: Record<FilterKind, string> = {
  all: "Tous", expense: "Dépenses", income: "Revenus", transfer: "Virements",
};

export interface OperationFilter {
  kind: FilterKind;
  categoryIDs: string[];
  accountID: string | null;
  tagIDs: string[];
  /// Montants en centimes.
  minCents: number | null;
  maxCents: number | null;
}

export const emptyFilter = (): OperationFilter =>
  ({ kind: "all", categoryIDs: [], accountID: null, tagIDs: [], minCents: null, maxCents: null });

export function isFilterActive(f: OperationFilter): boolean {
  return f.kind !== "all" || f.categoryIDs.length > 0 || f.accountID !== null || f.tagIDs.length > 0
    || f.minCents !== null || f.maxCents !== null;
}

export function matches(f: OperationFilter, t: Transaction): boolean {
  switch (f.kind) {
    case "all": break;
    case "expense": if (!isSpending(t)) return false; break;
    case "income": if (!isEarning(t)) return false; break;
    case "transfer": if (!isTransfer(t)) return false; break;
  }
  if (f.categoryIDs.length > 0 && !f.categoryIDs.includes(t.categoryID)) return false;
  if (f.tagIDs.length > 0 && !f.tagIDs.some(id => (t.tagIDs ?? []).includes(id))) return false;
  if (f.accountID !== null && resolvedAccountID(t) !== f.accountID) return false;
  if (f.minCents !== null && t.amountCents < f.minCents) return false;
  if (f.maxCents !== null && t.amountCents > f.maxCents) return false;
  return true;
}

/// Ajoute ou retire une valeur d'une liste (sélection multiple des filtres).
export const toggled = (list: string[], value: string) => (list.includes(value) ? list.filter(v => v !== value) : [...list, value]);

/// Minuscules sans accents (équivalent de la recherche « localizedStandardContains »).
export const foldText = (text: string) => text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();

/// La recherche porte sur la description, le nom de la catégorie et les tags.
export function matchesSearch(s: BudgetStore, t: Transaction, search: string): boolean {
  const query = foldText(search);
  if (foldText(t.note).includes(query) || foldText(s.categoryOf(t).label).includes(query)) return true;
  return (t.tagIDs ?? []).some(id => {
    const tag = s.tags.find(x => x.id === id);
    return tag !== undefined && foldText(tag.name).includes(query);
  });
}

// MARK: - Opérations Izly masquées (BudgetStore+Meals.swift)

/// Les opérations d'un compte Izly n'apparaissent pas individuellement dans l'écran Opérations
/// (elles restent dans le compte, le résumé du mois, les budgets et les statistiques).
export function isHiddenFromOperations(s: BudgetStore, t: Transaction): boolean {
  return s.accounts.find(a => a.id === resolvedAccountID(t))?.kind === "izly";
}

/// Dépenses Izly du mois (ligne récapitulative) : nombre et total en centimes.
export function izlySpending(s: BudgetStore, transactions: Transaction[]): { count: number; totalCents: number } {
  const spending = transactions.filter(t => isHiddenFromOperations(s, t) && isSpending(t));
  return { count: spending.length, totalCents: spending.reduce((sum, t) => sum + t.amountCents, 0) };
}
