// Instantané échangé entre appareils : port de SyncSnapshot (SyncMetadata.swift) et de BudgetStore+Sync.swift.
// Format du fichier Budget-sync.json : compatible avec l'app Mac (clés triées, dates en secondes depuis 2001).

import {
  type Obj, compactJSON, decodeAccount, decodeBudgetPlan, decodeCategory, decodeDate, decodeQuickExpense, decodeRecurring,
  decodeTag, decodeTransaction, encodeAccount, encodeBudgetPlan, encodeCategory, encodeDate, encodeQuickExpense,
  encodeRecurring, encodeTag, encodeTransaction, objects,
} from "../codec";
import {
  type Account, type BudgetPlan, type Category, type QuickExpense, type RecurringOperation, type Tag, type Transaction,
  MAIN_ACCOUNT_ID,
} from "../model";
import { decodeStamps, encodeStamps, metaIsEmpty } from "./tracker";
import type { BudgetStore } from "../store.svelte";

export const CURRENT_VERSION = 1;

/// Date « infiniment ancienne » (`Date.distantPast`) : un horodatage absent.
export const DISTANT_PAST = new Date(-8.64e15);

export interface SyncSnapshot {
  version: number;
  deviceID: string;
  date: Date;
  transactions: Transaction[];
  categories: Category[];
  quickExpenses: QuickExpense[];
  accounts: Account[];
  recurringOperations: RecurringOperation[];
  tags: Tag[];
  defaultAccountID: string;
  /// Optionnel : absent des fichiers écrits avant la page Budget.
  budgetPlan: BudgetPlan | null;
  modifiedAt: Record<string, Date>;
  deletedAt: Record<string, Date>;
  settingsAt: Record<string, Date>;
}

export function newSnapshot(deviceID: string, date: Date): SyncSnapshot {
  return { version: CURRENT_VERSION, deviceID, date, transactions: [], categories: [], quickExpenses: [], accounts: [],
           recurringOperations: [], tags: [], defaultAccountID: MAIN_ACCOUNT_ID, budgetPlan: null,
           modifiedAt: {}, deletedAt: {}, settingsAt: {} };
}

/// Instantané vide (distant inexistant).
export const emptySnapshot = (): SyncSnapshot => newSnapshot("", DISTANT_PAST);

export function encodeSnapshot(s: SyncSnapshot): Obj {
  const o: Obj = {
    version: s.version, deviceID: s.deviceID, date: encodeDate(s.date, "reference"),
    transactions: s.transactions.map(t => encodeTransaction(t, "reference")),
    categories: s.categories.map(encodeCategory),
    quickExpenses: s.quickExpenses.map(encodeQuickExpense),
    accounts: s.accounts.map(a => encodeAccount(a, "reference")),
    recurringOperations: s.recurringOperations.map(r => encodeRecurring(r, "reference")),
    tags: s.tags.map(encodeTag),
    defaultAccountID: s.defaultAccountID,
    modifiedAt: encodeStamps(s.modifiedAt), deletedAt: encodeStamps(s.deletedAt), settingsAt: encodeStamps(s.settingsAt),
  };
  if (s.budgetPlan) o.budgetPlan = encodeBudgetPlan(s.budgetPlan);
  return o;
}

/// Texte du fichier : JSON compact trié par clés (`JSONEncoder` `.sortedKeys`).
export const serializeSnapshot = (s: SyncSnapshot): string => compactJSON(encodeSnapshot(s));

/// Lit un instantané. Lève une erreur si une clé obligatoire manque (comme le décodeur synthétisé de Swift).
export function decodeSnapshot(o: Obj): SyncSnapshot {
  const arrays = ["transactions", "categories", "quickExpenses", "accounts", "recurringOperations", "tags"];
  const stamps = ["modifiedAt", "deletedAt", "settingsAt"];
  if (typeof o.version !== "number" || typeof o.deviceID !== "string" || (typeof o.date !== "number" && typeof o.date !== "string")
      || typeof o.defaultAccountID !== "string" || arrays.some(k => !Array.isArray(o[k]))
      || stamps.some(k => !o[k] || typeof o[k] !== "object")) {
    throw new Error("instantané illisible");
  }
  return {
    version: o.version, deviceID: o.deviceID, date: decodeDate(o.date),
    transactions: objects(o.transactions).map(decodeTransaction),
    categories: objects(o.categories).map(decodeCategory),
    quickExpenses: objects(o.quickExpenses).map(decodeQuickExpense),
    accounts: objects(o.accounts).map(decodeAccount),
    recurringOperations: objects(o.recurringOperations).map(decodeRecurring),
    tags: objects(o.tags).map(decodeTag),
    defaultAccountID: o.defaultAccountID,
    budgetPlan: o.budgetPlan && typeof o.budgetPlan === "object" ? decodeBudgetPlan(o.budgetPlan) : null,
    modifiedAt: decodeStamps(o.modifiedAt), deletedAt: decodeStamps(o.deletedAt), settingsAt: decodeStamps(o.settingsAt),
  };
}

/// Même contenu, sans tenir compte de l'appareil ni de la date d'écriture.
export function sameContent(a: SyncSnapshot, b: SyncSnapshot): boolean {
  const strip = (s: SyncSnapshot) => { const o = encodeSnapshot(s); o.deviceID = ""; o.date = 0; return compactJSON(o); };
  return strip(a) === strip(b);
}

// MARK: - Pont avec le magasin (BudgetStore+Sync.swift)

/// Appareil neuf : aucune donnée suivie (le premier échange adopte alors simplement le distant).
export const isSyncPristine = (s: BudgetStore): boolean => metaIsEmpty(s.sync.meta);

export function makeSyncSnapshot(s: BudgetStore): SyncSnapshot {
  return {
    version: CURRENT_VERSION, deviceID: s.sync.meta.deviceID, date: s.sync.clock(),
    transactions: s.transactions, categories: s.categories, quickExpenses: s.quickExpenses, accounts: s.accounts,
    recurringOperations: s.recurringOperations, tags: s.tags, defaultAccountID: s.defaultAccountID, budgetPlan: s.budgetPlan,
    modifiedAt: { ...s.sync.meta.modifiedAt }, deletedAt: { ...s.sync.meta.deletedAt }, settingsAt: { ...s.sync.meta.settingsAt },
  };
}

/// Remplace les données par le résultat d'une fusion (voir `BudgetStore.applyMergedData`). Renvoie vrai si quelque chose a changé.
export function applySyncSnapshot(s: BudgetStore, snap: SyncSnapshot): boolean {
  return s.applyMergedData(
    { categories: snap.categories, quickExpenses: snap.quickExpenses, accounts: snap.accounts,
      recurringOperations: snap.recurringOperations, defaultAccountID: snap.defaultAccountID, tags: snap.tags,
      budgetPlan: snap.budgetPlan ?? { savingsGoalCents: null, expectedIncomeCents: null }, transactions: snap.transactions },
    { modifiedAt: snap.modifiedAt, deletedAt: snap.deletedAt, settingsAt: snap.settingsAt });
}
