// Opérations récurrentes : calcul des échéances. Port de BudgetStore+Recurring.swift (partie calcul ;
// la création automatique des opérations et les modifications s'ajoutent dans ce même fichier).

import { newID, type RecurringOperation, type Transaction } from "../model";
import type { BudgetStore } from "../store.svelte";
import { addDays, daysInMonth, startOfDay } from "../dates";

/// n-ième échéance (0 = première), toujours calculée depuis `startDate`, au début du jour.
/// Le jour cible est borné au dernier jour du mois s'il n'existe pas (31 → 28/29 février).
export function occurrenceDate(op: RecurringOperation, n: number): Date {
  const start = startOfDay(op.startDate);
  let months: number;
  switch (op.frequency) {
    case "weekly": return addDays(start, 7 * n);
    case "monthly": months = n; break;
    case "quarterly": months = 3 * n; break;
    case "yearly": months = 12 * n; break;
  }
  const target = new Date(start.getFullYear(), start.getMonth() + months, 1);
  return new Date(target.getFullYear(), target.getMonth(), Math.min(start.getDate(), daysInMonth(target)));
}

/// Échéances comprises entre `from` et `to` (inclus), au maximum 500.
export function occurrences(op: RecurringOperation, from: Date, to: Date): Date[] {
  const lower = startOfDay(from).getTime();
  const upper = startOfDay(to).getTime();
  const end = op.endDate ? startOfDay(op.endDate).getTime() : null;
  const result: Date[] = [];
  for (let n = 0; n < 5000 && result.length < 500; n++) {
    const occ = occurrenceDate(op, n);
    const t = occ.getTime();
    if (t > upper || (end !== null && t > end)) break;
    if (t >= lower) result.push(occ);
  }
  return result;
}

/// Prochaine échéance strictement après `date` (null si la récurrente est terminée).
export function nextOccurrence(op: RecurringOperation, after: Date = new Date()): Date | null {
  const reference = startOfDay(after).getTime();
  const end = op.endDate ? startOfDay(op.endDate).getTime() : null;
  for (let n = 0; n < 5000; n++) {
    const occ = occurrenceDate(op, n);
    if (end !== null && occ.getTime() > end) return null;
    if (occ.getTime() > reference) return occ;
  }
  return null;
}

/// Montant signé d'une récurrente (négatif pour une dépense).
export const signedRecurring = (op: RecurringOperation) => (op.kind === "expense" ? -op.amountCents : op.amountCents);

/// Garde-fou : nombre maximal d'opérations créées par récurrente et par appel.
const MAX_GENERATED_PER_CALL = 500;

/// Crée les opérations des échéances passées non encore générées. Appelée au lancement.
export function generateDueRecurringOperations(s: BudgetStore, now: Date = new Date()): void {
  const today = startOfDay(now).getTime();
  const created: Transaction[] = [];
  const updated = [...s.recurringOperations];
  let changed = false;

  updated.forEach((operation, index) => {
    if (!operation.isActive) return;
    let last = operation.lastGeneratedDate;
    let count = 0;
    for (let n = 0; count < MAX_GENERATED_PER_CALL; n++) {
      const date = occurrenceDate(operation, n);
      if (date.getTime() > today) break;
      if (operation.endDate && date.getTime() > startOfDay(operation.endDate).getTime()) break;
      if (last && date.getTime() <= last.getTime()) continue;
      created.push({
        id: newID(), amountCents: operation.amountCents, kind: operation.kind, categoryID: operation.categoryID,
        note: operation.note.length === 0 ? operation.name : operation.note, date,
        accountID: s.accountIDForNewTransaction(operation.accountID), recurringID: operation.id, transferID: null,
        tagIDs: null, isAutoMeal: null,
      });
      last = date;
      count++;
    }
    if (last?.getTime() !== operation.lastGeneratedDate?.getTime()) {
      updated[index] = { ...operation, lastGeneratedDate: last };
      changed = true;
    }
  });

  if (changed) s.recurringOperations = updated;
  if (created.length > 0) {
    s.transactions = [...s.transactions, ...created];
    s.saveTransactions();
  }
  if (changed) s.saveSettings();
}

export function upsertRecurring(s: BudgetStore, operation: RecurringOperation) {
  s.registerUndo("Modifier la récurrente");
  const index = s.recurringOperations.findIndex(r => r.id === operation.id);
  s.recurringOperations = index >= 0 ? s.recurringOperations.with(index, operation) : [...s.recurringOperations, operation];
  s.saveSettings();
  generateDueRecurringOperations(s);
}

/// Supprime la récurrente ; les opérations déjà créées sont conservées.
export function deleteRecurring(s: BudgetStore, operation: RecurringOperation) {
  s.registerUndo("Supprimer la récurrente");
  s.recurringOperations = s.recurringOperations.filter(r => r.id !== operation.id);
  s.saveSettings();
}

/// Montant ramené au mois, en centimes (hebdo ×52/12, trimestriel /3, annuel /12).
export function monthlyAmountCents(op: RecurringOperation): number {
  switch (op.frequency) {
    case "weekly": return (op.amountCents * 52) / 12;
    case "monthly": return op.amountCents;
    case "quarterly": return op.amountCents / 3;
    case "yearly": return op.amountCents / 12;
  }
}
