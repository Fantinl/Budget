// Actions groupées sur plusieurs opérations : une seule étape d'annulation et une seule sauvegarde.
// Port de BudgetStore+Bulk.swift.

import { type Kind, type Transaction, isTransfer, newID, resolvedAccountID } from "../model";
import { BudgetStore } from "../store.svelte";

/// Applique une modification aux opérations données (les virements sont ignorés). `change` renvoie
/// l'opération modifiée. Renvoie le nombre d'opérations modifiées.
export function updateTransactions(s: BudgetStore, ids: Set<string>, change: (t: Transaction) => Transaction): number {
  if (!s.transactions.some(t => ids.has(t.id) && !isTransfer(t))) return 0;
  s.registerUndo("Modifier les opérations");
  let count = 0;
  s.transactions = s.transactions.map(t => {
    if (!ids.has(t.id) || isTransfer(t)) return t;
    count++;
    return change(t);
  });
  s.saveTransactions();
  return count;
}

/// Supprime les opérations données, avec la jambe jumelle des virements (même `transferID`).
/// Renvoie le nombre d'opérations supprimées.
export function deleteTransactions(s: BudgetStore, ids: Set<string>): number {
  const transferIDs = new Set(s.transactions.filter(t => ids.has(t.id) && t.transferID).map(t => t.transferID as string));
  const doomed = (t: Transaction) => ids.has(t.id) || (t.transferID !== null && transferIDs.has(t.transferID));
  const count = s.transactions.filter(doomed).length;
  if (count === 0) return 0;
  s.registerUndo(count > 1 ? "Supprimer les opérations" : "Supprimer l’opération");
  s.transactions = s.transactions.filter(t => !doomed(t));
  s.saveTransactions();
  return count;
}

/// Copie d'une opération : même date que l'original, sans lien récurrent.
export const copyOf = (t: Transaction): Transaction => ({ ...t, id: newID(), recurringID: null });

/// Copie les opérations (même date que l'original, sans lien récurrent) ; les virements sont ignorés.
/// Renvoie les copies créées.
export function duplicateTransactions(s: BudgetStore, ids: Set<string>): Transaction[] {
  const copies = s.transactions.filter(t => ids.has(t.id) && !isTransfer(t)).map(copyOf);
  if (copies.length === 0) return [];
  s.registerUndo("Dupliquer les opérations");
  s.transactions = [...s.transactions, ...copies];
  s.saveTransactions();
  return copies;
}

// MARK: - Tags en lot

/// État d'un tag dans une sélection.
export type BulkTagState = "all" | "some" | "none";

/// Identifiants donnés + jambe jumelle des virements (les tags valent pour les deux jambes).
function idsWithTransferTwins(s: BudgetStore, ids: Set<string>): Set<string> {
  const transferIDs = new Set(s.transactions.filter(t => ids.has(t.id) && t.transferID).map(t => t.transferID as string));
  if (transferIDs.size === 0) return ids;
  const all = new Set(ids);
  for (const t of s.transactions) if (t.transferID !== null && transferIDs.has(t.transferID)) all.add(t.id);
  return all;
}

/// Le tag est-il porté par toutes, certaines ou aucune des opérations ?
export function tagState(s: BudgetStore, tagID: string, ids: Set<string>): BulkTagState {
  const all = idsWithTransferTwins(s, ids);
  const targets = s.transactions.filter(t => all.has(t.id));
  const count = targets.filter(t => (t.tagIDs ?? []).includes(tagID)).length;
  if (count === 0) return "none";
  return count === targets.length ? "all" : "some";
}

function changeTags(s: BudgetStore, ids: Set<string>, name: string, change: (tagIDs: string[]) => string[]) {
  const all = idsWithTransferTwins(s, ids);
  if (!s.transactions.some(t => all.has(t.id))) return;
  s.registerUndo(name);
  s.transactions = s.transactions.map(t => {
    if (!all.has(t.id)) return t;
    const next = change(t.tagIDs ?? []);
    return { ...t, tagIDs: next.length === 0 ? null : next };
  });
  s.saveTransactions();
}

/// Ajoute le tag à toutes les opérations (virements compris, deux jambes).
export function addTagTo(s: BudgetStore, tagID: string, ids: Set<string>) {
  changeTags(s, ids, "Ajouter le tag", list => (list.includes(tagID) ? list : [...list, tagID]));
}

/// Retire le tag de toutes les opérations (virements compris, deux jambes).
export function removeTagFrom(s: BudgetStore, tagID: string, ids: Set<string>) {
  changeTags(s, ids, "Retirer le tag", list => list.filter(id => id !== tagID));
}

/// Retire tous les tags des opérations.
export function removeAllTags(s: BudgetStore, ids: Set<string>) {
  changeTags(s, ids, "Retirer les tags", () => []);
}

// MARK: - Modification groupée

/// Changements à appliquer ; un champ `undefined` n'est pas touché.
export interface BulkEdit {
  amountCents?: number;
  kind?: Kind;
  categoryID?: string;
  /// Identifiant de compte (principal inclus).
  accountID?: string;
  note?: string;
  addTagIDs: string[];
  removeTagIDs: string[];
}

export const emptyBulkEdit = (): BulkEdit => ({ addTagIDs: [], removeTagIDs: [] });

export function isBulkEditEmpty(e: BulkEdit): boolean {
  return e.amountCents === undefined && e.kind === undefined && e.categoryID === undefined && e.accountID === undefined
    && e.note === undefined && e.addTagIDs.length === 0 && e.removeTagIDs.length === 0;
}

/// Valeurs communes à une sélection : null quand les opérations diffèrent.
export interface BulkSummary {
  count: number;
  amountCents: number | null;
  kind: Kind | null;
  categoryID: string | null;
  accountID: string | null;
  note: string | null;
  tagIDs: string[] | null;
  firstDate: Date | null;
  lastDate: Date | null;
}

function common<V>(items: Transaction[], key: (t: Transaction) => V, same: (a: V, b: V) => boolean = (a, b) => a === b): V | null {
  if (items.length === 0) return null;
  const first = key(items[0]);
  return items.every(t => same(key(t), first)) ? first : null;
}

export function bulkSummary(items: Transaction[]): BulkSummary {
  const times = items.map(t => t.date.getTime());
  return {
    count: items.length,
    amountCents: common(items, t => t.amountCents),
    kind: common(items, t => t.kind),
    categoryID: common(items, t => t.categoryID),
    accountID: common(items, t => resolvedAccountID(t)),
    note: common(items, t => t.note),
    tagIDs: common(items, t => [...new Set(t.tagIDs ?? [])].sort(), (a, b) => a.join("\u0000") === b.join("\u0000")),
    firstDate: items.length ? new Date(Math.min(...times)) : null,
    lastDate: items.length ? new Date(Math.max(...times)) : null,
  };
}

/// Toutes les opérations ont les mêmes valeurs.
export const isUniform = (m: BulkSummary) =>
  m.count > 0 && m.amountCents !== null && m.kind !== null && m.categoryID !== null && m.accountID !== null
  && m.note !== null && m.tagIDs !== null;

/// Applique une modification groupée (virements ignorés, dates conservées) :
/// une seule annulation, une seule sauvegarde. Renvoie le nombre d'opérations modifiées.
export function applyBulkEdit(s: BudgetStore, ids: Set<string>, edit: BulkEdit): number {
  const count = s.transactions.filter(t => ids.has(t.id) && !isTransfer(t)).length;
  if (count === 0 || isBulkEditEmpty(edit)) return 0;
  s.registerUndo(count > 1 ? `Modifier ${count} opérations` : "Modifier l’opération");
  const stored = edit.accountID === undefined ? undefined : BudgetStore.storedAccountID(edit.accountID);
  s.transactions = s.transactions.map(source => {
    if (!ids.has(source.id) || isTransfer(source)) return source;
    let t = { ...source };
    if (edit.amountCents !== undefined) t.amountCents = edit.amountCents;
    if (edit.kind !== undefined) t.kind = edit.kind;
    if (stored !== undefined) t.accountID = stored;
    if (edit.note !== undefined) t.note = edit.note;
    t = applyCategory(s, edit, t);
    return applyTags(edit, t);
  });
  s.saveTransactions();
  return count;
}

/// Catégorie demandée si elle correspond au type final ; sinon, au changement de type, la première du type.
function applyCategory(s: BudgetStore, edit: BulkEdit, t: Transaction): Transaction {
  if (edit.categoryID !== undefined && s.category(edit.categoryID).kind === t.kind) {
    return { ...t, categoryID: edit.categoryID };
  }
  if (edit.kind !== undefined && s.category(t.categoryID).kind !== t.kind) {
    return { ...t, categoryID: s.categoriesFor(t.kind)[0]?.id ?? t.categoryID };
  }
  return t;
}

function applyTags(edit: BulkEdit, t: Transaction): Transaction {
  if (edit.addTagIDs.length === 0 && edit.removeTagIDs.length === 0) return t;
  let ids = (t.tagIDs ?? []).filter(id => !edit.removeTagIDs.includes(id));
  for (const id of edit.addTagIDs) if (!ids.includes(id)) ids = [...ids, id];
  return { ...t, tagIDs: ids.length === 0 ? null : ids };
}
