// Fusion pure de deux instantanés (aucune E/S) : port de SyncMerge.swift.
//
// Règles :
// - union par identifiant ; pour un même id, la version modifiée le plus récemment gagne ;
// - une suppression gagne si elle est strictement plus récente que la dernière modification ;
// - l'ordre d'une liste suit la version dont l'horodatage d'ordre est le plus récent, puis les éléments
//   qu'elle ne connaît pas sont ajoutés à la fin (dans l'ordre de l'autre) ;
// - un réglage simple (compte par défaut, plan du budget) : horodatage le plus récent ;
// - égalité parfaite : l'appareil au plus grand identifiant l'emporte (même résultat dans les deux sens) ;
// - les tombes de plus de 90 jours sont purgées.

import { SyncKey } from "./tracker";
import { DISTANT_PAST, type SyncSnapshot, newSnapshot } from "./snapshot";

export const TOMBSTONE_LIFETIME_MS = 90 * 24 * 3600 * 1000;

const time = (d: Date | undefined): number => (d ? d.getTime() : -Infinity);
const maxDate = (a: Date, b: Date): Date => (a.getTime() >= b.getTime() ? a : b);

export function mergeSnapshots(local: SyncSnapshot, remote: SyncSnapshot, now: Date = new Date()): SyncSnapshot {
  const ctx = new Context(local, remote);
  const out = newSnapshot(local.deviceID > remote.deviceID ? local.deviceID : remote.deviceID, maxDate(local.date, remote.date));

  const tx = ctx.records(SyncKey.transaction, local.transactions, remote.transactions, t => t.id);
  out.transactions = [...tx.values()].sort((a, b) => a.date.getTime() - b.date.getTime() || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const cats = ctx.records(SyncKey.category, local.categories, remote.categories, c => c.id);
  out.categories = ctx.ordered(SyncKey.orderCategories, cats, local.categories.map(c => c.id), remote.categories.map(c => c.id));
  const accs = ctx.records(SyncKey.account, local.accounts, remote.accounts, a => a.id);
  out.accounts = ctx.ordered(SyncKey.orderAccounts, accs, local.accounts.map(a => a.id), remote.accounts.map(a => a.id));
  const quick = ctx.records(SyncKey.quick, local.quickExpenses, remote.quickExpenses, q => q.id);
  out.quickExpenses = ctx.ordered(SyncKey.orderQuick, quick, local.quickExpenses.map(q => q.id), remote.quickExpenses.map(q => q.id));
  const recs = ctx.records(SyncKey.recurring, local.recurringOperations, remote.recurringOperations, r => r.id);
  out.recurringOperations = ctx.ordered(SyncKey.orderRecurring, recs, local.recurringOperations.map(r => r.id),
                                        remote.recurringOperations.map(r => r.id));
  const tags = ctx.records(SyncKey.tag, local.tags, remote.tags, t => t.id);
  out.tags = ctx.ordered(SyncKey.orderTags, tags, local.tags.map(t => t.id), remote.tags.map(t => t.id));

  const [account, accountStamp] = ctx.scalar(SyncKey.defaultAccount, local.defaultAccountID, remote.defaultAccountID);
  out.defaultAccountID = account;
  ctx.settingsAt[SyncKey.defaultAccount] = accountStamp;
  const [plan, planStamp] = ctx.scalar(SyncKey.budgetPlan, local.budgetPlan, remote.budgetPlan);
  out.budgetPlan = plan;
  ctx.settingsAt[SyncKey.budgetPlan] = planStamp;

  out.modifiedAt = ctx.modifiedAt;
  out.settingsAt = Object.fromEntries(Object.entries(ctx.settingsAt).filter(([, d]) => d.getTime() > DISTANT_PAST.getTime()));
  out.deletedAt = ctx.tombstones(now);
  return out;
}

/// Données de travail d'une fusion.
class Context {
  readonly preferLocal: boolean;
  survivors = new Set<string>();
  modifiedAt: Record<string, Date> = {};
  settingsAt: Record<string, Date> = {};

  constructor(readonly local: SyncSnapshot, readonly remote: SyncSnapshot) {
    this.preferLocal = local.deviceID >= remote.deviceID;
  }

  private pick(lStamp: Date | undefined, rStamp: Date | undefined): boolean {
    const l = time(lStamp), r = time(rStamp);
    return l !== r ? l > r : this.preferLocal;
  }

  /// Fusionne une collection : renvoie les enregistrements survivants par identifiant.
  records<T>(prefix: string, l: T[], r: T[], id: (t: T) => string): Map<string, T> {
    const first = (items: T[]) => { const m = new Map<string, T>(); for (const i of items) if (!m.has(id(i))) m.set(id(i), i); return m; };
    const lMap = first(l), rMap = first(r);
    const result = new Map<string, T>();
    for (const key of new Set([...lMap.keys(), ...rMap.keys()])) {
      const k = prefix + key;
      const lStamp = this.local.modifiedAt[k], rStamp = this.remote.modifiedAt[k];
      const li = lMap.get(key), ri = rMap.get(key);
      let item: T, stamp: Date | undefined;
      if (li !== undefined && ri !== undefined) {
        [item, stamp] = this.pick(lStamp, rStamp) ? [li, lStamp] : [ri, rStamp];
      } else if (li !== undefined) {
        [item, stamp] = [li, lStamp];
      } else {
        [item, stamp] = [ri as T, rStamp];
      }
      const deleted = Math.max(time(this.local.deletedAt[k]), time(this.remote.deletedAt[k]));
      if (deleted > time(stamp)) continue;
      result.set(key, item);
      this.survivors.add(k);
      if (stamp) this.modifiedAt[k] = stamp;
    }
    return result;
  }

  /// Ordre d'une liste : celui de la version la plus récente, puis les inconnus de l'autre.
  ordered<T>(key: string, items: Map<string, T>, l: string[], r: string[]): T[] {
    const lStamp = this.local.settingsAt[key], rStamp = this.remote.settingsAt[key];
    const useLocal = this.pick(lStamp, rStamp);
    this.settingsAt[key] = lStamp && rStamp ? maxDate(lStamp, rStamp) : (lStamp ?? rStamp ?? DISTANT_PAST);
    const seen = new Set<string>();
    const out: T[] = [];
    for (const id of useLocal ? [...l, ...r] : [...r, ...l]) {
      if (seen.has(id)) continue;
      seen.add(id);
      const item = items.get(id);
      if (item !== undefined) out.push(item);
    }
    return out;
  }

  /// Réglage simple : la valeur la plus récemment modifiée.
  scalar<V>(key: string, l: V, r: V): [V, Date] {
    const lStamp = this.local.settingsAt[key], rStamp = this.remote.settingsAt[key];
    const useLocal = this.pick(lStamp, rStamp);
    return [useLocal ? l : r, lStamp && rStamp ? maxDate(lStamp, rStamp) : (lStamp ?? rStamp ?? DISTANT_PAST)];
  }

  /// Tombes conservées : celles des enregistrements non survivants, de moins de 90 jours.
  tombstones(now: Date): Record<string, Date> {
    const out: Record<string, Date> = {};
    const cutoff = now.getTime() - TOMBSTONE_LIFETIME_MS;
    const all: Record<string, Date> = { ...this.local.deletedAt };
    for (const [k, d] of Object.entries(this.remote.deletedAt)) all[k] = all[k] && all[k].getTime() >= d.getTime() ? all[k] : d;
    for (const [k, d] of Object.entries(all)) if (!this.survivors.has(k) && d.getTime() >= cutoff) out[k] = d;
    return out;
  }
}
