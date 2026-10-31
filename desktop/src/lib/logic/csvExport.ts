// Export CSV des opérations. Port de CSVExport.swift (la feuille d'export des réglages appelle ces fonctions).

import { type Transaction, isTransfer, kindLabel, signedCents } from "../model";
import { addMonths, monthInterval, startOfDay, startOfYear } from "../dates";
import type { BudgetStore } from "../store.svelte";

/// Période exportable en CSV.
export type CSVPeriod = "thisMonth" | "lastMonth" | "thisYear" | "all" | "custom";
export const csvPeriods: CSVPeriod[] = ["thisMonth", "lastMonth", "thisYear", "all", "custom"];
export const csvPeriodLabel: Record<CSVPeriod, string> = {
  thisMonth: "Ce mois-ci", lastMonth: "Mois dernier", thisYear: "Cette année", all: "Tout", custom: "Dates personnalisées",
};

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/// Intervalle [début, fin[ ; null = sans limite. Pour « custom », `to` est inclus (les dates peuvent être inversées).
export function csvInterval(period: CSVPeriod, from: Date, to: Date, now: Date = new Date()): { start: Date; end: Date } | null {
  switch (period) {
    case "thisMonth": return monthInterval(now);
    case "lastMonth": return monthInterval(addMonths(now, -1));
    case "thisYear": {
      const start = startOfYear(now);
      return { start, end: new Date(start.getFullYear() + 1, 0, 1) };
    }
    case "all": return null;
    case "custom": {
      const [first, last] = from.getTime() <= to.getTime() ? [from, to] : [to, from];
      const start = startOfDay(first);
      const lastDay = startOfDay(last);
      return { start, end: new Date(lastDay.getFullYear(), lastDay.getMonth(), lastDay.getDate() + 1) };
    }
  }
}

const ymd = (d: Date) => `${pad(d.getFullYear(), 4)}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

export function csvFileName(period: CSVPeriod, from: Date, to: Date, now: Date = new Date()): string {
  switch (period) {
    case "thisMonth": return `Budget-${ymd(now).slice(0, 7)}.csv`;
    case "lastMonth": return `Budget-${ymd(addMonths(now, -1)).slice(0, 7)}.csv`;
    case "thisYear": return `Budget-${pad(now.getFullYear(), 4)}.csv`;
    case "all": return "Budget-tout.csv";
    case "custom": {
      const [first, last] = from.getTime() <= to.getTime() ? [from, to] : [to, from];
      return `Budget-${ymd(first)}_${ymd(last)}.csv`;
    }
  }
}

/// Opérations d'une période (celles de l'intervalle [début, fin[ ; toutes si « Tout »).
export function transactionsForPeriod(s: BudgetStore, period: CSVPeriod, from: Date, to: Date, now: Date = new Date()): Transaction[] {
  const interval = csvInterval(period, from, to, now);
  return interval ? s.transactions.filter(t => t.date >= interval.start && t.date < interval.end) : [...s.transactions];
}

/// Entoure de guillemets si le champ contient « ; », « " » ou un retour à la ligne.
export function csvEscape(field: string): string {
  if (!/[;"\n\r]/.test(field)) return field;
  return `"${field.replaceAll('"', '""')}"`;
}

/// Montant signé en centimes → « -700,00 » (virgule, sans séparateur de milliers).
function amountText(cents: number): string {
  const abs = Math.abs(cents);
  return `${cents < 0 ? "-" : ""}${Math.floor(abs / 100)},${pad(abs % 100)}`;
}

const dateText = (d: Date) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${pad(d.getFullYear(), 4)}`;

/// CSV UTF-8 avec BOM (Excel) en tête du texte, séparateur « ; », décimale « , », dates jj/mm/aaaa,
/// dépenses en négatif, lignes séparées par CRLF.
export function csvText(s: BudgetStore, transactions: Transaction[]): string {
  const header = ["Date", "Type", "Catégorie", "Compte", "Description", "Montant"].map(csvEscape).join(";");
  const lines = [header];
  for (const t of [...transactions].sort((a, b) => a.date.getTime() - b.date.getTime())) {
    // Un virement apparaît comme tel (et non comme dépense/revenu sans catégorie).
    const fields = [dateText(t.date), isTransfer(t) ? "Virement" : kindLabel[t.kind],
                    isTransfer(t) ? "Virement" : s.categoryOf(t).label, s.account(t.accountID).name, t.note, amountText(signedCents(t))];
    lines.push(fields.map(csvEscape).join(";"));
  }
  return "﻿" + lines.join("\r\n") + "\r\n";
}
