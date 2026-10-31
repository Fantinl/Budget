// Suivi des modifications pour la synchronisation : port de SyncMetadata.swift (SyncKey, SyncMetadata, SyncTracker).
// Les métadonnées vivent dans sync-meta.json (dates en secondes depuis 2001, comme l'app Mac).

import { type Obj, compactJSON, decodeDate, encodeAccount, encodeBudgetPlan, encodeCategory, encodeDate, encodeQuickExpense,
         encodeRecurring, encodeTag, encodeTransaction } from "../codec";
import { newID } from "../model";
import type { BudgetStore } from "../store.svelte";

/// Clés des enregistrements : « type:identifiant ».
export const SyncKey = {
  transaction: "tx:",
  category: "cat:",
  account: "acc:",
  quick: "quick:",
  recurring: "rec:",
  tag: "tag:",
  defaultAccount: "defaultAccount",
  budgetPlan: "budgetPlan",
  orderCategories: "order.categories",
  orderAccounts: "order.accounts",
  orderQuick: "order.quickExpenses",
  orderTags: "order.tags",
  orderRecurring: "order.recurring",
} as const;

export const simpleSettingKeys = [SyncKey.defaultAccount, SyncKey.budgetPlan, SyncKey.orderCategories, SyncKey.orderAccounts,
                                  SyncKey.orderQuick, SyncKey.orderTags, SyncKey.orderRecurring];

export interface SyncMetadata {
  deviceID: string;
  modifiedAt: Record<string, Date>;
  deletedAt: Record<string, Date>;
  settingsAt: Record<string, Date>;
}

export const emptyMeta = (): SyncMetadata => ({ deviceID: newID(), modifiedAt: {}, deletedAt: {}, settingsAt: {} });
export const metaIsEmpty = (m: SyncMetadata) =>
  Object.keys(m.modifiedAt).length === 0 && Object.keys(m.deletedAt).length === 0 && Object.keys(m.settingsAt).length === 0;

export function encodeStamps(stamps: Record<string, Date>): Obj {
  const o: Obj = {};
  for (const [k, d] of Object.entries(stamps)) o[k] = encodeDate(d, "reference");
  return o;
}

export function decodeStamps(v: unknown): Record<string, Date> {
  const out: Record<string, Date> = {};
  if (v && typeof v === "object") for (const [k, d] of Object.entries(v as Obj)) out[k] = decodeDate(d);
  return out;
}

export const encodeMeta = (m: SyncMetadata): Obj => ({
  deviceID: m.deviceID, modifiedAt: encodeStamps(m.modifiedAt), deletedAt: encodeStamps(m.deletedAt), settingsAt: encodeStamps(m.settingsAt),
});

export function decodeMeta(o: Obj): SyncMetadata {
  return { deviceID: typeof o.deviceID === "string" ? o.deviceID : newID(), modifiedAt: decodeStamps(o.modifiedAt),
           deletedAt: decodeStamps(o.deletedAt), settingsAt: decodeStamps(o.settingsAt) };
}

/// Forme comparable d'un enregistrement (équivalent de l'égalité des structs Swift).
const fingerprint = (o: Obj) => compactJSON(o);

/// État de référence : ce qui a été enregistré la dernière fois. Chaque enregistrement est gardé sous forme d'empreinte JSON.
export interface SyncBaseline {
  transactions: Map<string, string>;
  categories: Map<string, string>;
  quickExpenses: Map<string, string>;
  accounts: Map<string, string>;
  recurring: Map<string, string>;
  tags: Map<string, string>;
  orders: Record<string, string[]>;
  defaultAccountID: string;
  budgetPlan: string;
}

function index<T>(items: readonly T[], key: (t: T) => string, encode: (t: T) => Obj): Map<string, string> {
  const map = new Map<string, string>();
  for (const item of items) { const k = key(item); if (!map.has(k)) map.set(k, fingerprint(encode(item))); }
  return map;
}

function orders(s: BudgetStore): Record<string, string[]> {
  return {
    [SyncKey.orderCategories]: s.categories.map(c => c.id),
    [SyncKey.orderAccounts]: s.accounts.map(a => a.id),
    [SyncKey.orderQuick]: s.quickExpenses.map(q => q.id),
    [SyncKey.orderTags]: s.tags.map(t => t.id),
    [SyncKey.orderRecurring]: s.recurringOperations.map(r => r.id),
  };
}

/// L'ordre a changé pour les éléments présents avant et après (ajouts et suppressions ne comptent pas).
export function relativeOrderChanged(old: string[], now: string[]): boolean {
  const oldSet = new Set(old), newSet = new Set(now);
  const a = old.filter(id => newSet.has(id)), b = now.filter(id => oldSet.has(id));
  return a.length !== b.length || a.some((id, i) => id !== b[i]);
}

/// Compare l'état courant au dernier état enregistré et tient les horodatages à jour.
/// Appelé par `saveTransactions()` / `saveSettings()` : les fonctions de mutation n'ont pas à s'en soucier.
export class SyncTracker {
  meta: SyncMetadata = emptyMeta();
  baseline: SyncBaseline | null = null;
  /// Vrai pendant l'application d'une synchronisation.
  isSuspended = false;
  clock: () => Date = () => new Date();
  /// Appelé après une modification locale (le coordinateur y accroche son anti-rebond).
  onLocalChange: (() => void) | null = null;

  static makeBaseline(s: BudgetStore): SyncBaseline {
    return {
      transactions: index(s.transactions, t => t.id, t => encodeTransaction(t, "reference")),
      categories: index(s.categories, c => c.id, encodeCategory),
      quickExpenses: index(s.quickExpenses, q => q.id, encodeQuickExpense),
      accounts: index(s.accounts, a => a.id, a => encodeAccount(a, "reference")),
      recurring: index(s.recurringOperations, r => r.id, r => encodeRecurring(r, "reference")),
      tags: index(s.tags, t => t.id, encodeTag),
      orders: orders(s),
      defaultAccountID: s.defaultAccountID,
      budgetPlan: fingerprint(encodeBudgetPlan(s.budgetPlan)),
    };
  }

  /// Fin du chargement. 1er chargement : métadonnées lues (`loaded`), ou tout est daté par la date des fichiers.
  /// Rechargements (restauration, import) : les différences comptent comme des modifications.
  didReload(s: BudgetStore, loaded: SyncMetadata | null, fileDates: { transactions: Date | null; settings: Date | null }) {
    if (this.baseline === null) {
      if (loaded) this.meta = loaded;
      else { this.meta = emptyMeta(); this.stampExisting(s, fileDates); }
      this.baseline = SyncTracker.makeBaseline(s);
      return;
    }
    this.trackTransactions(s);
    this.trackSettings(s);
  }

  private stampExisting(s: BudgetStore, fileDates: { transactions: Date | null; settings: Date | null }) {
    const m = this.meta;
    if (fileDates.transactions) for (const t of s.transactions) m.modifiedAt[SyncKey.transaction + t.id] = fileDates.transactions;
    const date = fileDates.settings;
    if (!date) return;
    for (const c of s.categories) m.modifiedAt[SyncKey.category + c.id] = date;
    for (const a of s.accounts) m.modifiedAt[SyncKey.account + a.id] = date;
    for (const q of s.quickExpenses) m.modifiedAt[SyncKey.quick + q.id] = date;
    for (const r of s.recurringOperations) m.modifiedAt[SyncKey.recurring + r.id] = date;
    for (const t of s.tags) m.modifiedAt[SyncKey.tag + t.id] = date;
    for (const k of simpleSettingKeys) m.settingsAt[k] = date;
  }

  trackTransactions(s: BudgetStore) {
    const base = this.baseline;
    if (this.isSuspended || !base) return;
    const changed = this.track(s.transactions, SyncKey.transaction, base, "transactions", t => t.id, t => encodeTransaction(t, "reference"));
    this.finish(changed, s);
  }

  trackSettings(s: BudgetStore) {
    const base = this.baseline;
    if (this.isSuspended || !base) return;
    let changed = this.track(s.categories, SyncKey.category, base, "categories", c => c.id, encodeCategory);
    changed = this.track(s.accounts, SyncKey.account, base, "accounts", a => a.id, a => encodeAccount(a, "reference")) || changed;
    changed = this.track(s.quickExpenses, SyncKey.quick, base, "quickExpenses", q => q.id, encodeQuickExpense) || changed;
    changed = this.track(s.recurringOperations, SyncKey.recurring, base, "recurring", r => r.id, r => encodeRecurring(r, "reference")) || changed;
    changed = this.track(s.tags, SyncKey.tag, base, "tags", t => t.id, encodeTag) || changed;
    changed = this.trackSimpleSettings(s, base) || changed;
    this.finish(changed, s);
  }

  private trackSimpleSettings(s: BudgetStore, base: SyncBaseline): boolean {
    const now = this.clock();
    let changed = false;
    if (base.defaultAccountID !== s.defaultAccountID) {
      this.meta.settingsAt[SyncKey.defaultAccount] = now;
      base.defaultAccountID = s.defaultAccountID;
      changed = true;
    }
    const plan = fingerprint(encodeBudgetPlan(s.budgetPlan));
    if (base.budgetPlan !== plan) {
      this.meta.settingsAt[SyncKey.budgetPlan] = now;
      base.budgetPlan = plan;
      changed = true;
    }
    for (const [key, ids] of Object.entries(orders(s))) {
      if (relativeOrderChanged(base.orders[key] ?? [], ids)) { this.meta.settingsAt[key] = now; changed = true; }
      base.orders[key] = ids;
    }
    return changed;
  }

  private track<T>(items: readonly T[], prefix: string, base: SyncBaseline,
                   field: "transactions" | "categories" | "quickExpenses" | "accounts" | "recurring" | "tags",
                   key: (t: T) => string, encode: (t: T) => Obj): boolean {
    const now = this.clock();
    const old = base[field];
    const current = new Map<string, string>();
    let changed = false;
    for (const item of items) {
      const id = key(item);
      const print = fingerprint(encode(item));
      current.set(id, print);
      if (old.get(id) !== print) {
        this.meta.modifiedAt[prefix + id] = now;
        delete this.meta.deletedAt[prefix + id];
        changed = true;
      }
    }
    for (const id of old.keys()) {
      if (!current.has(id)) {
        this.meta.deletedAt[prefix + id] = now;
        delete this.meta.modifiedAt[prefix + id];
        changed = true;
      }
    }
    base[field] = current;
    return changed;
  }

  private finish(changed: boolean, s: BudgetStore) {
    if (!changed) return;
    void s.persistSyncMeta();
    this.onLocalChange?.();
  }
}
