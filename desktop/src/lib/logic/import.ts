// Import de relevés : port de BudgetStore+Import.swift et ImportRecharge.swift.

import { type Kind, type Transaction, IZLY_RECHARGE_KEYWORDS, MAIN_ACCOUNT_ID, newID, resolvedAccountID } from "../model";
import { BudgetStore } from "../store.svelte";
import { normalize } from "../statement/text";

/// Catégorie et libellé par défaut des virements (BudgetStore+Transfers.swift).
const TRANSFER_CATEGORY_ID = "transfer";
const DEFAULT_TRANSFER_NOTE = "Virement";

/// Recharge Izly repérée dans un relevé : devient un virement vers le compte Izly à l'import.
export interface ImportRecharge {
  amountCents: number;
  date: Date;
  note: string;
  izlyAccountID: string;
}

/// Le libellé contient un mot-clé de recharge (sans tenir compte de la casse ni des accents).
export function isRechargeLabel(label: string): boolean {
  const text = normalize(label);
  return IZLY_RECHARGE_KEYWORDS.some(k => text.includes(normalize(k)));
}

/// Ajoute les opérations importées en une seule fois (une seule sauvegarde).
/// Chaque recharge devient un virement `account` → compte Izly, le tout dans la même action annulable.
export function addImported(s: BudgetStore, imported: Transaction[], recharges: ImportRecharge[] = [], account: string = MAIN_ACCOUNT_ID) {
  s.registerUndo("Importer le relevé");
  if (imported.length === 0 && recharges.length === 0) return;
  const added = [...imported];
  for (const recharge of recharges) {
    if (recharge.izlyAccountID === account || recharge.amountCents <= 0) continue;
    const id = newID();
    const note = recharge.note.trim();
    const text = note.length === 0 ? DEFAULT_TRANSFER_NOTE : note;
    const leg = (kind: Kind, accountID: string): Transaction => ({
      id: newID(), amountCents: recharge.amountCents, kind, categoryID: TRANSFER_CATEGORY_ID, note: text, date: recharge.date,
      accountID: BudgetStore.storedAccountID(accountID), recurringID: null, transferID: id, tagIDs: null, isAutoMeal: null,
    });
    added.push(leg("expense", account), leg("income", recharge.izlyAccountID));
  }
  s.transactions = [...s.transactions, ...added];
  s.saveTransactions();
}

const dayKey = (d: Date) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;

export function duplicateKey(date: Date, kind: Kind, amountCents: number, accountID: string): string {
  return `${dayKey(date)}|${kind}|${amountCents}|${accountID}`;
}

export function duplicateLabelKey(date: Date, label: string, accountID: string): string {
  return `${dayKey(date)}|${normalize(label)}|${accountID}`;
}

export interface DuplicateIndex { amounts: Map<string, number>; labels: Set<string> }

/// Clés « jour|type|montant|compte » des opérations existantes, avec leur nombre.
export function duplicateIndex(s: BudgetStore): DuplicateIndex {
  const amounts = new Map<string, number>();
  const labels = new Set<string>();
  for (const t of s.transactions) {
    const key = duplicateKey(t.date, t.kind, t.amountCents, resolvedAccountID(t));
    amounts.set(key, (amounts.get(key) ?? 0) + 1);
    if (t.note.length > 0) labels.add(duplicateLabelKey(t.date, t.note, resolvedAccountID(t)));
  }
  return { amounts, labels };
}

/// Même jour, type, montant et compte (chaque opération existante ne compte qu'une fois), ou même libellé le même jour.
/// Consomme l'entrée correspondante de l'index.
export function consumeDuplicate(index: DuplicateIndex, date: Date, kind: Kind, amountCents: number, label: string, accountID: string): boolean {
  const key = duplicateKey(date, kind, amountCents, accountID);
  const count = index.amounts.get(key);
  if (count !== undefined && count > 0) { index.amounts.set(key, count - 1); return true; }
  return index.labels.has(duplicateLabelKey(date, label, accountID));
}
