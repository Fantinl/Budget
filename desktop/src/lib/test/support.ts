// Aides pour les tests (équivalent de Tests/BudgetTests/TestSupport.swift).
// Le magasin écrit sur un faux disque en mémoire (platform.ts hors de Tauri).
import { BudgetStore } from "../store.svelte";
import { newID, type Kind, type Transaction } from "../model";

/// Magasin neuf dans un dossier vide ; `dir` permet de recharger le même dossier.
export async function makeStore(dir = `/test/${newID()}`): Promise<BudgetStore> {
  const s = new BudgetStore(dir);
  await s.reloadFromDisk();
  return s;
}

/// Date locale à midi (évite les effets de fuseau).
export const day = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h);

export function op(amountEuros: number, fields: Partial<Transaction> & { kind?: Kind } = {}): Transaction {
  return { id: newID(), amountCents: Math.round(amountEuros * 100), kind: "expense", categoryID: "otherExpense", note: "",
           date: day(2026, 10, 17), accountID: null, recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null, ...fields };
}

export const expense = (euros: number, categoryID = "otherExpense", date = day(2026, 10, 17)) => op(euros, { categoryID, date });
export const income = (euros: number, date = day(2026, 10, 17), categoryID = "salary") => op(euros, { kind: "income", categoryID, date });

/// Laisse passer la fin de l'action en cours (regroupement d'annulation, écritures).
export const tick = () => new Promise<void>(r => setTimeout(r, 0));
