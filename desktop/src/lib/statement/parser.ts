// Lecture d'un relevé bancaire (CSV, Excel, OFX/QFX, texte) : port de StatementParser.swift. Logique pure.
// Les montants sont en centimes entiers ; un montant signé est négatif pour une dépense.

import type { Kind } from "../model";
import { StatementError } from "./errors";
import { htmlGrid, xlsxGrid, dateText } from "./spreadsheet";
import { collapseSpaces, decimalStringToCents, normalize, trimSpaces } from "./text";

export { normalize } from "./text";
export { StatementError } from "./errors";

/// Ligne lisible d'un relevé. Le montant est signé : négatif = dépense, positif = revenu.
export interface StatementRow {
  date: Date;
  label: string;
  signedCents: number;
}

export const rowKind = (r: StatementRow): Kind => (r.signedCents < 0 ? "expense" : "income");
export const rowAmount = (r: StatementRow): number => Math.abs(r.signedCents);

/// Numéros de colonnes (à partir de 0) choisis pour lire un CSV.
export interface StatementColumns {
  date: number | null;
  label: number | null;
  amount: number | null;
  debit: number | null;
  credit: number | null;
}

export const emptyColumns = (): StatementColumns => ({ date: null, label: null, amount: null, debit: null, credit: null });
/// Vrai si le montant vient de deux colonnes débit / crédit.
export const isSplit = (c: StatementColumns) => c.amount === null && (c.debit !== null || c.credit !== null);

/// Tableau brut d'un CSV, une fois l'en-tête repéré.
export interface StatementTable {
  headers: string[];
  rows: string[][];
  columns: StatementColumns;
}

export interface StatementResult {
  rows: StatementRow[];
  skipped: number;
}

export type StatementContent = { table: StatementTable } | { result: StatementResult };

// MARK: - Point d'entrée

const startsWith = (data: Uint8Array, bytes: number[]) => bytes.every((b, i) => data[i] === b);

/// Le contenu décide du format, l'extension n'est qu'un indice.
export async function parseStatement(data: Uint8Array): Promise<StatementContent> {
  if (startsWith(data, [0x50, 0x4b, 0x03, 0x04])) {
    const grid = await xlsxGrid(data);
    const table = tableFromGrid(grid);
    if (!table) throw new StatementError("empty");
    normalizeSerialDates(table);
    return { table };
  }
  if (startsWith(data, [0xd0, 0xcf, 0x11, 0xe0])) throw new StatementError("legacyExcel");

  const text = decodeText(data);
  if (text.length === 0) throw new StatementError("unreadable");
  if (/<STMTTRN>/i.test(text)) {
    const result = parseOFX(text);
    if (result.rows.length === 0) throw new StatementError("empty");
    return { result };
  }
  if (isHTMLTable(text)) {
    const table = tableFromGrid(htmlGrid(text));
    if (!table) throw new StatementError("empty");
    return { table };
  }
  const table = parseCSV(text);
  if (!table) throw new StatementError("empty");
  return { table };
}

/// Faux .xls : un tableau HTML.
function isHTMLTable(text: string): boolean {
  const head = text.slice(0, 4096).trim().toLowerCase();
  return head.startsWith("<") && (head.includes("<table") || head.includes("<tr"));
}

/// Filet de sécurité : nombres de série Excel (20000 à 80000) dans la colonne de date → jj/mm/aaaa.
function normalizeSerialDates(table: StatementTable) {
  const column = table.columns.date;
  if (column === null) return;
  for (const row of table.rows) {
    if (column >= row.length) continue;
    const cell = row[column];
    const serial = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(cell) ? Number(cell) : NaN;
    if (serial >= 20000 && serial <= 80000) row[column] = dateText(serial);
  }
}

// MARK: - Encodage

/// Octets que Windows-1252 n'assigne pas : Swift refuse alors ce codage et retombe sur Latin 1.
const CP1252_UNDEFINED = new Set([0x81, 0x8d, 0x8f, 0x90, 0x9d]);

/// UTF-8 d'abord, sinon Windows-1252, sinon Latin 1 (qui accepte tous les octets).
export function decodeText(input: Uint8Array): string {
  let data = input;
  if (startsWith(data, [0xef, 0xbb, 0xbf])) data = data.subarray(3);
  if (startsWith(data, [0xff, 0xfe])) return new TextDecoder("utf-16le").decode(data.subarray(2));
  if (startsWith(data, [0xfe, 0xff])) return new TextDecoder("utf-16be").decode(data.subarray(2));
  try {
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(data);
  } catch { /* pas de l'UTF-8 */ }
  if (!data.some(b => CP1252_UNDEFINED.has(b))) return new TextDecoder("windows-1252").decode(data);
  // Latin 1 pur (le « latin1 » du WHATWG est en fait Windows-1252) : un octet = un caractère.
  let text = "";
  for (let i = 0; i < data.length; i += 8192) text += String.fromCharCode(...data.subarray(i, i + 8192));
  return text;
}

// MARK: - CSV

export function parseCSV(text: string): StatementTable | null {
  let best: StatementTable | null = null;
  let fallback: { records: string[][]; score: number } | null = null;

  for (const delimiter of [";", "\t", ","]) {
    const records = tokenize(text, delimiter);
    // À égalité, le premier séparateur gagne.
    if (best === null) best = headerTable(records);
    const score = records.slice(0, 5).reduce((sum, r) => sum + r.length, 0);
    if (fallback === null || score > fallback.score) fallback = { records, score };
  }
  if (best) return best;
  return fallback ? fallbackTable(fallback.records) : null;
}

/// Grille → tableau : en-têtes repérés, sinon première ligne en en-têtes.
export function tableFromGrid(grid: string[][]): StatementTable | null {
  const records = grid.filter(row => row.some(c => c.length > 0));
  return headerTable(records) ?? fallbackTable(records);
}

/// Tableau dont la ligne d'en-têtes (date + montant ou débit/crédit) a été reconnue.
function headerTable(records: string[][]): StatementTable | null {
  const index = headerIndex(records);
  if (index === null) return null;
  const headers = records[index];
  const rows = records.slice(index + 1).filter(row => row.some(c => c.length > 0));
  return { headers, rows, columns: detectColumns(headers) };
}

/// Aucun en-tête reconnu : première ligne = en-têtes, l'utilisateur choisira les colonnes.
function fallbackTable(records: string[][]): StatementTable | null {
  const first = records[0];
  if (!first || first.length <= 1) return null;
  const rows = records.slice(1).filter(row => row.some(c => c.length > 0));
  return { headers: first, rows, columns: emptyColumns() };
}

/// Découpe le texte en enregistrements (guillemets, guillemets doublés, retours à la ligne dans un champ).
export function tokenize(text: string, delimiter: string): string[][] {
  const records: string[][] = [];
  let record: string[] = [];
  let field = "";
  let inQuotes = false;

  const endRecord = () => {
    record.push(trimSpaces(field));
    field = "";
    if (record.some(f => f.length > 0)) records.push(record);
    record = [];
  };

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === "\"") {
        if (text[i + 1] === "\"") { field += "\""; i++; } else inQuotes = false;
      } else field += c;
    } else if (c === "\"") {
      inQuotes = true;
    } else if (c === delimiter) {
      record.push(trimSpaces(field));
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;   // « \r\n » est un seul saut de ligne
      endRecord();
    } else {
      field += c;
    }
  }
  if (field.length > 0 || record.length > 0) endRecord();
  return records;
}

/// Première ligne (parmi les 40 premières) qui ressemble à des en-têtes : date + montant (ou débit/crédit).
function headerIndex(records: string[][]): number | null {
  for (let index = 0; index < Math.min(40, records.length); index++) {
    const record = records[index];
    if (record.length < 2) continue;
    const columns = detectColumns(record);
    if (columns.date === null) continue;
    const others = [columns.amount, columns.debit, columns.credit].filter((x): x is number => x !== null);
    if (others.some(o => o !== columns.date)) return index;
  }
  return null;
}

// MARK: - Détection des colonnes

export function detectColumns(headers: string[]): StatementColumns {
  const names = headers.map(normalize);

  const best = (score: (name: string) => number): number | null => {
    let result: { index: number; score: number } | null = null;
    names.forEach((name, index) => {
      const value = score(name);
      if (value > 0 && value > (result?.score ?? 0)) result = { index, score: value };
    });
    return (result as { index: number } | null)?.index ?? null;
  };

  const date = best(name => {
    if (!name.includes("date")) return 0;
    if (name === "date") return 100;
    if (name.includes("operation") || name.includes("dateop")) return 90;
    if (name.includes("comptab")) return 80;
    if (name.includes("valeur") || name.includes("dateval")) return 10;
    return 50;
  });
  const label = best(name => {
    if (name.includes("date") || name.includes("categor")) return 0;
    if (name.startsWith("libelle") || name === "label") return 100;
    if (name.includes("description") || name.includes("intitule")) return 90;
    if (name.includes("libelle")) return 80;
    if (name.includes("operation") || name.includes("motif") || name.includes("objet")) return 60;
    if (name.includes("detail") || name.includes("beneficiaire") || name.includes("tiers")) return 40;
    if (name === "nom" || name === "name" || name === "memo") return 30;
    return 0;
  });
  const amount = best(name => {
    if (name === "montant" || name === "amount") return 100;
    if (name.startsWith("montant") && !name.includes("devise")) return 60;
    return 0;
  });
  const debit = best(name => (name.includes("debit") ? (name.startsWith("debit") ? 100 : 60) : 0));
  const credit = best(name => (name.includes("credit") ? (name.startsWith("credit") ? 100 : 60) : 0));
  return { date, label, amount, debit, credit };
}

// MARK: - Lecture des lignes

/// Transforme le tableau en opérations avec les colonnes choisies ; les lignes illisibles sont comptées.
export function rowsFromTable(table: StatementTable, columns: StatementColumns): StatementResult {
  const rows: StatementRow[] = [];
  let skipped = 0;
  const cell = (row: string[], index: number | null) => (index !== null && index >= 0 && index < row.length ? row[index] : "");

  for (const row of table.rows) {
    const date = columns.date !== null ? parseDate(cell(row, columns.date)) : null;
    if (!date) { skipped++; continue; }
    const label = cleanLabel(cell(row, columns.label));

    let signed: number | null = null;
    if (columns.amount !== null) {
      signed = parseAmount(cell(row, columns.amount));
    } else {
      const debit = parseAmount(cell(row, columns.debit));
      const credit = parseAmount(cell(row, columns.credit));
      if (debit !== null && debit !== 0) signed = -Math.abs(debit);
      else if (credit !== null && credit !== 0) signed = Math.abs(credit);
    }
    if (signed === null || signed === 0) { skipped++; continue; }
    rows.push({ date, label: label.length === 0 ? "Sans libellé" : label, signedCents: signed });
  }
  return { rows, skipped };
}

/// Espaces multiples réduits, extrémités nettoyées.
export const cleanLabel = collapseSpaces;

// MARK: - Dates

const asInt = (s: string): number | null => (/^[+-]?\d+$/.test(s) ? Number(s) : null);

/// jj/mm/aaaa, jj/mm/aa, jj-mm-aaaa, jj.mm.aaaa, aaaa-mm-jj, aaaammjj (heure ignorée).
export function parseDate(text: string): Date | null {
  let s = text.trim();
  const end = s.search(/[ T]/);
  if (end >= 0) s = s.slice(0, end);
  if (s.length === 0) return null;
  // OFX : « 20240315120000[+1:CET] » → on garde les chiffres du début.
  const leading = /^\p{N}*/u.exec(s)![0];
  if ([...leading].length >= 8) s = leading;

  let numbers: number[] = [];
  let lengths: number[] = [];
  if (/^\p{N}+$/u.test(s) && [...s].length >= 8) {
    const digits = [...s];
    numbers = [digits.slice(0, 4).join(""), digits.slice(4, 6).join(""), digits.slice(6, 8).join("")]
      .map(asInt).filter((n): n is number => n !== null);
    lengths = [4, 2, 2];
  } else {
    const parts = s.split(/[/\-.]/).filter(p => p.length > 0);
    if (parts.length !== 3) return null;
    for (const part of parts) {
      const value = asInt(part);
      if (value === null) return null;
      numbers.push(value);
      lengths.push([...part].length);
    }
  }
  if (numbers.length !== 3) return null;

  let [day, month, year] = lengths[0] === 4 ? [numbers[2], numbers[1], numbers[0]] : [numbers[0], numbers[1], numbers[2]];
  if (year < 100) year += 2000;
  if (day < 1 || day > 31 || month < 1 || month > 12 || year < 1990 || year > 2100) return null;
  const date = new Date(year, month - 1, day, 12);
  return date.getDate() === day ? date : null;
}

// MARK: - Montants

/// « -1 234,56 », « 1234.56 », « 1 234,56 € », « 12,50- », « (12,50) » → centimes signés, null si illisible.
export function parseAmount(text: string): number | null {
  let s = text.toUpperCase();
  for (const junk of ["EUR", "€", " ", " ", " ", "+", "'"]) s = s.split(junk).join("");
  if (s.length === 0) return null;

  let negative = false;
  if (s.startsWith("(") && s.endsWith(")")) { negative = true; s = s.slice(1, -1); }
  if (s.endsWith("-")) { negative = true; s = s.slice(0, -1); }
  if (s.startsWith("-")) { negative = true; s = s.slice(1); }
  if (s.length === 0 || !/^[0-9,.]+$/.test(s)) return null;

  // Le dernier séparateur est la virgule décimale ; les autres sont des milliers.
  const lastComma = s.lastIndexOf(","), lastDot = s.lastIndexOf(".");
  const count = (ch: string) => s.split(ch).length - 1;
  let decimalIndex = -1;
  if (lastComma >= 0 && lastDot >= 0) decimalIndex = Math.max(lastComma, lastDot);
  else if (lastComma >= 0) decimalIndex = count(",") === 1 ? lastComma : -1;
  else if (lastDot >= 0) decimalIndex = count(".") === 1 ? lastDot : -1;

  let normalized = "";
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "," || c === ".") { if (i === decimalIndex) normalized += "."; } else normalized += c;
  }
  const cents = decimalStringToCents(normalized);
  if (cents === null) return null;
  return negative ? -cents : cents;
}

// MARK: - OFX

export function parseOFX(text: string): StatementResult {
  const rows: StatementRow[] = [];
  let skipped = 0;
  for (const block of text.split("<STMTTRN>").slice(1)) {
    const dateText = ofxValue("DTPOSTED", block);
    const amountText = ofxValue("TRNAMT", block);
    const date = dateText === null ? null : parseDate(dateText);
    const amount = amountText === null ? null : parseAmount(amountText);
    if (!date || amount === null || amount === 0) { skipped++; continue; }
    const name = ofxValue("NAME", block) ?? "";
    const memo = ofxValue("MEMO", block) ?? "";
    let label = name.length === 0 ? memo : name;
    if (name.length > 0 && memo.length > 0 && !name.toLowerCase().includes(memo.toLowerCase())
        && !memo.toLowerCase().includes(name.toLowerCase())) {
      label += " " + memo;
    }
    label = cleanLabel(unescapeXML(label));
    rows.push({ date, label: label.length === 0 ? "Sans libellé" : label, signedCents: amount });
  }
  return { rows, skipped };
}

/// Valeur d'une balise OFX (avec ou sans balise fermante).
function ofxValue(tag: string, block: string): string | null {
  const start = block.search(new RegExp(`<${tag}>`, "i"));
  if (start < 0) return null;
  const rest = block.slice(start + tag.length + 2);
  const end = rest.search(/[<\n\r]/);
  const value = trimSpaces(end < 0 ? rest : rest.slice(0, end));
  return value.length === 0 ? null : value;
}

function unescapeXML(text: string): string {
  return text.replaceAll("&amp;", "&").replaceAll("&lt;", "<").replaceAll("&gt;", ">")
             .replaceAll("&apos;", "'").replaceAll("&quot;", "\"");
}
