// Brouillon de compte en cours d'édition (AccountDraft de AccountEditor.swift) et lecture des montants saisis.

import { type Account, accountKinds, newAccount } from "../../lib/model";
import { hasRegulatedRate } from "../../lib/logic/rates";
import { hidesBank } from "../../lib/logic/accounts";

export interface AccountDraft {
  account: Account;
  balanceText: string;
  rateText: string;
  marketValueText: string;
  marketValueDate: Date;
  bankText: string;
  /// Le nom est encore celui proposé automatiquement : on le recalcule quand le type ou la banque change.
  nameIsAuto: boolean;
  isNew: boolean;
}

const plainNumber = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2, useGrouping: false });

/// Montant à mettre dans un champ (vide pour 0).
const formatNumber = (value: number) => (value === 0 ? "" : plainNumber.format(value));

/// Accepte « 1 234,50 », « -20.5 » ; null si illisible ou vide.
export function parseDecimal(text: string): number | null {
  const cleaned = text.replace(/,/g, ".").replace(/\s/g, "");
  return /^[+-]?(\d+\.?\d*|\.\d+)$/.test(cleaned) ? Number(cleaned) : null;
}

export const isBlank = (text: string) => text.trim().length === 0;

export function newDraft(colorIndex: number): AccountDraft {
  const account = newAccount({ name: "", kind: "checking", colorIndex: Math.max(colorIndex, 0) });
  const draft: AccountDraft = { account, balanceText: "", rateText: "", marketValueText: "", marketValueDate: new Date(),
                                bankText: "", nameIsAuto: true, isNew: true };
  draft.account.name = suggestedName(draft);
  return draft;
}

export function draftFrom(account: Account): AccountDraft {
  return {
    account: { ...account },
    balanceText: formatNumber(account.initialBalanceCents / 100),
    rateText: account.interestRate === null ? "" : formatNumber(account.interestRate),
    marketValueText: account.marketValueCents === null ? "" : formatNumber(account.marketValueCents / 100),
    marketValueDate: account.marketValueDate ?? new Date(),
    bankText: account.bank ?? "",
    nameIsAuto: false,
    isNew: false,
  };
}

/// Solde initial en centimes : vide = 0 ; null si illisible.
export function parsedBalanceCents(d: AccountDraft): number | null {
  if (isBlank(d.balanceText)) return 0;
  const v = parseDecimal(d.balanceText);
  return v === null ? null : Math.round(v * 100);
}

export const trimmedBank = (d: AccountDraft) => d.bankText.trim();
export const showsRate = (d: AccountDraft) => accountKinds[d.account.kind].family === "savings";
/// Taux réglementé automatique actif pour ce brouillon.
export const autoRateActive = (d: AccountDraft) => hasRegulatedRate(d.account.kind) && d.account.autoRate !== false;

/// Nom proposé : « Livret A », « Compte courant Boursorama », « PEA Trade Republic ».
export function suggestedName(d: AccountDraft): string {
  const base = accountKinds[d.account.kind].label;
  const bank = trimmedBank(d);
  return bank.length === 0 || hidesBank(d.account.kind) ? base : `${base} ${bank}`;
}

/// Recalcule le nom s'il est encore automatique.
export function refreshName(d: AccountDraft) {
  if (d.nameIsAuto || d.account.name.trim().length === 0) {
    d.account.name = suggestedName(d);
    d.nameIsAuto = true;
  }
}

/// Valide les champs ; null si l'un des montants est illisible.
export function validated(d: AccountDraft): Account | null {
  const name = d.account.name.trim();
  const balance = parsedBalanceCents(d);
  if (name.length === 0 || balance === null) return null;
  const result: Account = { ...d.account, name, initialBalanceCents: balance };
  const bank = trimmedBank(d);
  result.bank = bank.length === 0 || hidesBank(d.account.kind) ? null : bank;
  if (!hasRegulatedRate(d.account.kind)) result.autoRate = null;
  if (d.account.kind !== "pel") result.openingDate = null;
  if (showsRate(d) && !autoRateActive(d) && !isBlank(d.rateText)) {
    const rate = parseDecimal(d.rateText);
    if (rate === null) return null;
    result.interestRate = rate;
  } else {
    result.interestRate = null;
  }
  if (accountKinds[d.account.kind].family === "investment" || d.account.kind === "assuranceVie") {
    if (!isBlank(d.marketValueText)) {
      const value = parseDecimal(d.marketValueText);
      if (value === null) return null;
      result.marketValueCents = Math.round(value * 100);
      result.marketValueDate = d.marketValueDate;
    } else {
      result.marketValueCents = null;
      result.marketValueDate = null;
    }
  } else {
    result.marketValueCents = null;
    result.marketValueDate = null;
  }
  return result;
}
