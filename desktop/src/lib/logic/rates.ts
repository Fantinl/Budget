// Taux réglementés (Livret A, LDDS, LEP, CEL, Livret Jeune, PEL). Port de BudgetStore+Rates.swift et RateService.swift.
// Seul un GET est envoyé : aucune donnée personnelle.

import type { Account, AccountKind } from "../model";
import { join, readText, writeText } from "../platform";
import { pref } from "../prefs.svelte";
import type { BudgetStore } from "../store.svelte";
import { type RateTable, rateState } from "./rateState.svelte";

export { embeddedRates, type RateTable } from "./rateState.svelte";

export const RATES_REMOTE_URL = "https://raw.githubusercontent.com/Fantinl/Budget/main/rates.json";
const REFRESH_INTERVAL_MS = 7 * 86_400_000;
const lastCheck = pref<number | null>("rates.lastCheck", null);

/// Taux réglementé retenu pour un compte (en %).
export interface RegulatedRate {
  rate: number;
  since: Date | null;
  /// Plancher (Livret Jeune) : la banque peut faire mieux.
  isMinimum: boolean;
}

/// Taux fixé par l'État (ou plancher réglementaire) : peut être renseigné automatiquement.
export const hasRegulatedRate = (kind: AccountKind) =>
  ["livretA", "ldds", "lep", "livretJeune", "pel", "cel"].includes(kind);

/// Taux automatique actif (type réglementé et `autoRate` non désactivé).
export const usesAutoRate = (a: Pick<Account, "kind" | "autoRate">) => hasRegulatedRate(a.kind) && a.autoRate !== false;

/// Date « yyyy-MM-dd » lue en fuseau de Paris (minuit à Paris), null si illisible.
export function parseRateDate(text: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const paris = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Paris", year: "numeric", month: "numeric", day: "numeric",
                                                   hour: "numeric", hourCycle: "h23" });
  const isMidnightOfDay = (date: Date) => {
    const p = Object.fromEntries(paris.formatToParts(date).map(x => [x.type, Number(x.value)]));
    return p.year === y && p.month === mo && p.day === d && p.hour === 0;
  };
  for (const offset of [1, 2]) {
    const candidate = new Date(Date.UTC(y, mo - 1, d) - offset * 3_600_000);
    if (isMidnightOfDay(candidate)) return candidate;
  }
  return new Date(Date.UTC(y, mo - 1, d) - 3_600_000);
}

/// Taux réglementé pour un type de compte (PEL : selon la date d'ouverture).
export function regulatedRateFor(kind: AccountKind, openingDate: Date | null, table: RateTable = rateState.table): RegulatedRate | null {
  switch (kind) {
    case "livretA": case "ldds": case "lep": case "livretJeune": case "cel": {
      const entry = table.rates[kind];
      if (!entry) return null;
      return { rate: entry.rate, since: parseRateDate(entry.since), isMinimum: kind === "livretJeune" };
    }
    case "pel": {
      if (!openingDate) return null;
      let best: { from: Date; rate: number } | null = null;
      for (const e of table.pel) {
        const from = parseRateDate(e.from);
        if (from && from.getTime() <= openingDate.getTime() && (!best || from.getTime() > best.from.getTime())) best = { from, rate: e.rate };
      }
      return best ? { rate: best.rate, since: best.from, isMinimum: false } : null;
    }
    default:
      return null;
  }
}

/// Taux réglementé en vigueur pour ce compte.
export function regulatedRate(_s: BudgetStore | null, account: Account): RegulatedRate | null {
  if (!hasRegulatedRate(account.kind)) return null;
  return regulatedRateFor(account.kind, account.openingDate);
}

/// Taux affiché : réglementé si automatique, sinon celui saisi.
export function effectiveRate(s: BudgetStore | null, account: Account): number | null {
  if (usesAutoRate(account)) {
    const regulated = regulatedRate(s, account);
    if (regulated) return regulated.rate;
  }
  return account.interestRate;
}

function parseTable(text: string): RateTable | null {
  try {
    const v = JSON.parse(text);
    if (v && typeof v.version === "number" && typeof v.updatedAt === "string" && typeof v.source === "string"
        && v.rates && typeof v.rates === "object" && Array.isArray(v.pel)) return v as RateTable;
  } catch { /* illisible */ }
  return null;
}

async function loadCache(directory: string) {
  if (rateState.cacheLoaded) return;
  rateState.cacheLoaded = true;
  const text = await readText(join(directory, "rates.json")).catch(() => null);
  const cached = text ? parseTable(text) : null;
  if (cached && cached.updatedAt > rateState.table.updatedAt) rateState.table = cached;
}

/// Au lancement : relit le cache, puis télécharge si la dernière vérification a plus de 7 jours.
export async function refreshRates(s: BudgetStore, force = false): Promise<void> {
  await loadCache(s.directory);
  const last = lastCheck.value;
  if (!force && last !== null && Date.now() - last < REFRESH_INTERVAL_MS) return;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(RATES_REMOTE_URL, { method: "GET", cache: "no-store", signal: controller.signal });
    if (response.status !== 200) return;
    const text = await response.text();
    const remote = parseTable(text);
    if (!remote) return;
    // On ne garde que des taux plus récents ou égaux à ceux déjà connus.
    if (remote.updatedAt >= rateState.table.updatedAt) {
      rateState.table = remote;
      await writeText(join(s.directory, "rates.json"), text).catch(() => {});
    }
    lastCheck.value = Date.now();
  } catch {
    /* hors ligne : on réessaiera au prochain lancement */
  } finally {
    clearTimeout(timer);
  }
}
