// Ajustement de solde : on recopie le solde réel, Budget enregistre la différence. Port de BudgetStore+Adjust.swift.

import { type Account, newID, type Transaction } from "../model";
import { BudgetStore } from "../store.svelte";
import { balance } from "./accounts";

/// Écart entre le solde réel et celui de Budget, en centimes (négatif = dépenses non notées).
export function balanceGap(s: BudgetStore, account: Account, realBalanceCents: number, asOf: Date = new Date()): number {
  return realBalanceCents - balance(s, account, asOf);
}

/// Crée la dépense (écart négatif) ou le revenu (écart positif) qui ramène le solde à `realBalanceCents`.
/// Rien si l'écart est nul. `categoryID` sert pour une dépense ; un revenu va en « Autre revenu ».
export function adjustBalance(
  s: BudgetStore, account: Account, realBalanceCents: number,
  options: { date?: Date; categoryID: string; note: string },
): Transaction | null {
  const date = options.date ?? new Date();
  const gap = balanceGap(s, account, realBalanceCents, date);
  if (gap === 0) return null;
  s.registerUndo("Ajuster le solde");
  const transaction: Transaction = {
    id: newID(), amountCents: Math.abs(gap), kind: gap < 0 ? "expense" : "income",
    categoryID: gap < 0 ? options.categoryID : "otherIncome", note: options.note, date,
    accountID: BudgetStore.storedAccountID(account.id), recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null,
  };
  s.transactions = [...s.transactions, transaction];
  s.saveTransactions();
  return transaction;
}
