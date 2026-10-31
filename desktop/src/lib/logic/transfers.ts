// Virements : deux opérations liées par `transferID` (dépense sur la source, revenu sur la destination).
// Port de BudgetStore+Transfers.swift.

import { type Account, type Kind, type Transaction, newID } from "../model";
import { BudgetStore } from "../store.svelte";

export const TRANSFER_CATEGORY_ID = "transfer";
export const DEFAULT_TRANSFER_NOTE = "Virement";

/// Les deux jambes d'un virement (sortante, entrante), null si incomplet.
export function transferLegs(s: BudgetStore, id: string): { out: Transaction; in: Transaction } | null {
  const legs = s.transactions.filter(t => t.transferID === id);
  const out = legs.find(t => t.kind === "expense");
  const incoming = legs.find(t => t.kind === "income");
  return out && incoming ? { out, in: incoming } : null;
}

/// Compte situé de l'autre côté du virement.
export function counterpartAccount(s: BudgetStore, t: Transaction): Account | null {
  if (!t.transferID) return null;
  const legs = transferLegs(s, t.transferID);
  if (!legs) return null;
  const other = t.kind === "expense" ? legs.in : legs.out;
  return s.account(other.accountID);
}

const cleanTransferNote = (note: string) => (note.trim().length === 0 ? DEFAULT_TRANSFER_NOTE : note.trim());

function makeLeg(kind: Kind, transferID: string, account: string, amountCents: number, date: Date, note: string): Transaction {
  return { id: newID(), amountCents, kind, categoryID: TRANSFER_CATEGORY_ID, note, date,
           accountID: BudgetStore.storedAccountID(account), recurringID: null, transferID, tagIDs: null, isAutoMeal: null };
}

/// Crée un virement ; renvoie son identifiant (null si refusé : mêmes comptes ou montant ≤ 0).
export function createTransfer(s: BudgetStore, from: string, to: string, amountCents: number, date: Date, note: string): string | null {
  if (from === to || !(amountCents > 0)) return null;
  s.registerUndo("Créer un virement");
  const id = newID();
  const clean = cleanTransferNote(note);
  s.transactions = [...s.transactions,
    makeLeg("expense", id, from, amountCents, date, clean),
    makeLeg("income", id, to, amountCents, date, clean)];
  s.saveTransactions();
  return id;
}

export function updateTransfer(s: BudgetStore, id: string, from: string, to: string, amountCents: number, date: Date, note: string) {
  if (from === to || !(amountCents > 0) || !transferLegs(s, id)) return;
  s.registerUndo("Modifier le virement");
  const clean = cleanTransferNote(note);
  s.transactions = s.transactions.map(t => (t.transferID === id
    ? { ...t, accountID: BudgetStore.storedAccountID(t.kind === "expense" ? from : to), amountCents, date, note: clean }
    : t));
  s.saveTransactions();
}

export function deleteTransfer(s: BudgetStore, id: string) {
  s.registerUndo("Supprimer le virement");
  s.transactions = s.transactions.filter(t => t.transferID !== id);
  s.saveTransactions();
}
