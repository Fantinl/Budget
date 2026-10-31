// Lecture des tableurs (.xlsx, .xls « HTML ») en grille de texte : port de SpreadsheetReader.swift. Logique pure.

import { StatementError } from "./errors";
import { centsToDecimalString, collapseSpaces, decimalStringToCents } from "./text";
import { parseXML } from "./xml";
import { ZipArchive } from "./zip";

// MARK: - Dates et nombres Excel

/// Jours depuis le 30/12/1899 → « jj/mm/aaaa » (la fraction d'heure est ignorée).
export function dateText(serial: number): string {
  const d = new Date((Math.floor(serial) - 25569) * 86_400_000);
  const pad = (n: number, w: number) => String(n).padStart(w, "0");
  return `${pad(d.getUTCDate(), 2)}/${pad(d.getUTCMonth() + 1, 2)}/${pad(d.getUTCFullYear(), 4)}`;
}

/// Nombre Excel (point décimal, notation scientifique possible) → texte arrondi au centime.
export function numberText(raw: string): string {
  const cents = decimalStringToCents(raw);
  return cents === null ? raw : centsToDecimalString(cents);
}

const DOUBLE = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;
const asDouble = (s: string): number | null => (DOUBLE.test(s) ? Number(s) : null);

// MARK: - xlsx

/// Grille de la première feuille non vide d'un classeur .xlsx.
export async function xlsxGrid(data: Uint8Array): Promise<string[][]> {
  let zip: ZipArchive;
  try { zip = new ZipArchive(data); } catch { throw new StatementError("excelUnreadable"); }
  const file = async (path: string): Promise<string | null> => {
    try { return await zip.readText(path); } catch { return null; }
  };

  const sharedXML = await file("xl/sharedStrings.xml");
  const shared = sharedXML ? sharedStrings(sharedXML) : [];
  const stylesXML = await file("xl/styles.xml");
  const dateStyles = new Set(stylesXML ? dateStyleIndexes(stylesXML) : []);

  // Feuilles dans l'ordre du classeur.
  let sheetPaths: string[] = [];
  const workbook = await file("xl/workbook.xml");
  if (workbook) {
    const ids = sheetIDs(workbook);
    const relsXML = await file("xl/_rels/workbook.xml.rels");
    const targets = relsXML ? relationshipTargets(relsXML) : {};
    for (const id of ids) {
      let target = targets[id];
      if (target === undefined) continue;
      target = target.startsWith("/") ? target.slice(1) : "xl/" + target;
      sheetPaths.push(target);
    }
  }
  if (sheetPaths.length === 0) sheetPaths = ["xl/worksheets/sheet1.xml"];

  let best: string[][] = [];
  let anyFile = false;
  for (const path of sheetPaths) {
    const sheet = await file(path);
    if (sheet === null) continue;
    anyFile = true;
    const grid = sheetGrid(sheet, shared, dateStyles);
    const count = grid.filter(row => row.some(c => c.length > 0)).length;
    if (count > 0) return grid;   // première feuille non vide
    if (count > best.length) best = grid;
  }
  if (best.length === 0 && !anyFile) throw new StatementError("excelUnreadable");
  return best;
}

// MARK: - Parseurs XML

function sharedStrings(xml: string): string[] {
  const strings: string[] = [];
  let current = "", inT = false, phoneticDepth = 0;
  parseXML(xml, {
    start(name) {
      if (name === "si") current = "";
      else if (name === "t") inT = true;
      else if (name === "rPh") phoneticDepth++;
    },
    text(t) { if (inT && phoneticDepth === 0) current += t; },
    end(name) {
      if (name === "t") inT = false;
      else if (name === "rPh") phoneticDepth--;
      else if (name === "si") strings.push(current);
    },
  });
  return strings;
}

function dateStyleIndexes(xml: string): number[] {
  const custom = new Map<number, string>();
  const formatIDs: number[] = [];
  let inCellXfs = false;
  parseXML(xml, {
    start(name, a) {
      if (name === "numFmt") {
        const id = intOrNull(a.numFmtId);
        if (id !== null && a.formatCode !== undefined) custom.set(id, a.formatCode);
      } else if (name === "cellXfs") inCellXfs = true;
      else if (name === "xf" && inCellXfs) formatIDs.push(intOrNull(a.numFmtId) ?? 0);
    },
    end(name) { if (name === "cellXfs") inCellXfs = false; },
  });
  return formatIDs.flatMap((id, index) => (isDateFormat(id, custom.get(id)) ? [index] : []));
}

export function isDateFormat(id: number, custom: string | undefined): boolean {
  if ((id >= 14 && id <= 22) || (id >= 45 && id <= 47)) return true;
  if (custom === undefined) return false;
  // On retire les textes entre guillemets, les crochets ([$€-40C], [Red]) et les caractères échappés.
  let code = custom;
  for (const pattern of [/"[^"]*"/g, /\[[^\]]*\]/g, /\\./g]) code = code.replace(pattern, "");
  return /[dmy]/.test(code.toLowerCase());
}

function sheetIDs(xml: string): string[] {
  const ids: string[] = [];
  parseXML(xml, {
    start(name, a) {
      if (name !== "sheet") return;
      const key = Object.keys(a).find(k => k === "id" || k.endsWith(":id"));
      if (key !== undefined) ids.push(a[key]);
    },
  });
  return ids;
}

function relationshipTargets(xml: string): Record<string, string> {
  const targets: Record<string, string> = {};
  parseXML(xml, { start(name, a) { if (name === "Relationship" && a.Id !== undefined && a.Target !== undefined) targets[a.Id] = a.Target; } });
  return targets;
}

const intOrNull = (s: string | undefined): number | null => (s !== undefined && /^[+-]?\d+$/.test(s) ? Number(s) : null);

/// « C5 » → (colonne 2, ligne 4).
function position(ref: string): { column: number; row: number } | null {
  let col = 0, digits = "";
  for (const ch of ref.toUpperCase()) {
    if (ch >= "A" && ch <= "Z" && digits === "") col = col * 26 + ch.charCodeAt(0) - 64;
    else if (ch >= "0" && ch <= "9") digits += ch;
  }
  if (col <= 0) return null;
  return { column: col - 1, row: (digits === "" ? 0 : Number(digits)) - 1 };
}

function sheetGrid(xml: string, shared: string[], dateStyles: Set<number>): string[][] {
  const grid: string[][] = [];
  let rowIndex = -1, column = 0, type = "", style = 0, text = "", capturing = false, inInline = false;

  const place = (value: string) => {
    while (grid.length <= rowIndex) grid.push([]);
    while (grid[rowIndex].length <= column) grid[rowIndex].push("");
    grid[rowIndex][column] = value;
  };

  parseXML(xml, {
    start(name, a) {
      switch (name) {
        case "row": {
          const r = intOrNull(a.r);
          if (r !== null && r > 0) rowIndex = r - 1; else rowIndex += 1;
          column = -1;
          break;
        }
        case "c": {
          column += 1;
          const pos = a.r !== undefined ? position(a.r) : null;
          if (pos) { column = pos.column; if (pos.row >= 0) rowIndex = pos.row; }
          if (rowIndex < 0) rowIndex = 0;
          type = a.t ?? "";
          style = intOrNull(a.s) ?? 0;
          text = "";
          break;
        }
        case "v": capturing = true; break;
        case "is": inInline = true; break;
        case "t": if (inInline) capturing = true; break;
      }
    },
    text(t) { if (capturing) text += t; },
    end(name) {
      switch (name) {
        case "v": case "t": capturing = false; break;
        case "is": inInline = false; break;
        case "c": {
          const raw = text.trim();
          let value = "";
          switch (type) {
            case "s": { const i = intOrNull(raw); value = i !== null && i >= 0 && i < shared.length ? shared[i] : ""; break; }
            case "inlineStr": case "str": case "e": value = text; break;
            case "b": value = raw === "1" ? "VRAI" : "FAUX"; break;
            default: {
              const serial = asDouble(raw);
              if (raw === "") value = "";
              else if (dateStyles.has(style) && serial !== null) value = dateText(serial);
              else value = numberText(raw);
            }
          }
          value = value.trim();
          if (value.length > 0) place(value);
          break;
        }
      }
    },
  });
  return grid;
}

// MARK: - HTML (faux .xls)

export function htmlGrid(html: string): string[][] {
  const rowRegex = /<tr\b[^>]*>(.*?)(?=<\/tr\s*>|<tr\b|<\/table|$)/gis;
  const cellRegex = /<t[dh]\b[^>]*>(.*?)(?=<\/t[dh]\s*>|<t[dh]\b|<\/tr|$)/gis;
  const grid: string[][] = [];
  for (const row of html.matchAll(rowRegex)) {
    const cells = [...row[1].matchAll(cellRegex)].map(m => cleanHTML(m[1]));
    if (cells.some(c => c.length > 0)) grid.push(cells);
  }
  return grid;
}

/// Retire les balises, décode les entités, normalise les espaces.
function cleanHTML(fragment: string): string {
  let s = fragment.replace(/<br\s*\/?>/gi, " ");
  s = s.replace(/<[^>]*>/g, "");
  return collapseSpaces(decodeEntities(s));
}

const ENTITIES: Record<string, string> = {
  nbsp: " ", amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'",
  eacute: "é", egrave: "è", ecirc: "ê", euml: "ë", agrave: "à", acirc: "â", auml: "ä",
  ccedil: "ç", icirc: "î", iuml: "ï", ocirc: "ô", ouml: "ö", ugrave: "ù", ucirc: "û", uuml: "ü",
  Eacute: "É", Egrave: "È", Ecirc: "Ê", Agrave: "À", Acirc: "Â", Ccedil: "Ç", Icirc: "Î",
  Ocirc: "Ô", Ugrave: "Ù", oelig: "œ", OElig: "Œ", euro: "€", laquo: "«", raquo: "»",
  deg: "°", rsquo: "’", lsquo: "‘", hellip: "…", ndash: "–", mdash: "—", middot: "·",
};

/// Décode en un seul passage (pas de double décodage de « &amp;lt; »).
function decodeEntities(text: string): string {
  if (!text.includes("&")) return text;
  return text.replace(/&(#[xX]?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);/g, (whole, name: string) => {
    if (name.startsWith("#")) {
      const body = name.slice(1);
      const hex = body[0] === "x" || body[0] === "X";
      const digits = hex ? body.slice(1) : body;
      if (!(hex ? /^[0-9A-Fa-f]+$/ : /^\d+$/).test(digits)) return whole;
      const code = parseInt(digits, hex ? 16 : 10);
      // Valeurs scalaires Unicode seulement (ni substituts ni au-delà de U+10FFFF).
      if (code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return whole;
      return String.fromCodePoint(code);
    }
    return ENTITIES[name] ?? whole;
  });
}
