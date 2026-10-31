// Interprétation d'une saisie express (« café 2,5 hier »). Port de ExpressEntryParser.swift.
// Fonctions pures : testables sans interface. Montants en centimes.

import { type Category, type Kind, type QuickExpense, type Transaction, fallbackCategoryID } from "../model";
import { addDays, addMonths, daysInMonth, isSameDay, startOfDay, startOfMonth, weekday } from "../dates";
import { evaluate } from "./amountExpression";

export interface ExpressEntry {
  amountCents: number | null;
  kind: Kind;
  date: Date;
  label: string;
}

const weekdays: Record<string, number> = {   // dimanche = 1
  dimanche: 1, lundi: 2, mardi: 3, mercredi: 4, jeudi: 5, vendredi: 6, samedi: 7,
};
const incomeWords = new Set(["salaire", "paie", "paye", "remboursement", "rembt", "prime", "rembourse", "cpam", "ameli"]);
const incomePhrases = ["virement recu"];

/// Minuscules sans accents, apostrophe droite.
export function fold(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replaceAll("’", "'");
}

const capitalizeFirst = (text: string) => (text.length === 0 ? text : text.charAt(0).toUpperCase() + text.slice(1));

/// Retire les espaces autour des opérateurs entre deux chiffres (« 12 + 8,5 » devient « 12+8,5 »).
const collapseOperators = (text: string) => text.replace(/(?<=[\d)€])\s*([+×*÷/])\s*(?=[\d(])/g, "$1");

// MARK: - Dates

/// Midi : évite les décalages de fuseau ou d'heure d'été.
const noon = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12, 0, 0);
const shift = (d: Date, days: number) => noon(addDays(d, days));

/// Jour de semaine le plus proche dans le passé (aujourd'hui compris).
function lastWeekday(target: number, now: Date): Date {
  const back = (weekday(now) - target + 7) % 7;
  return back === 0 ? now : shift(now, -back);
}

/// « Le 25 » : ce mois-ci, ou le mois précédent si le jour est dans le futur (ou inexistant).
function dayOfMonth(day: number, now: Date): Date {
  const today = startOfDay(now);
  let month = startOfMonth(now);
  for (let i = 0; i < 13; i++) {
    if (day <= daysInMonth(month)) {
      const candidate = new Date(month.getFullYear(), month.getMonth(), day);
      if (candidate.getTime() <= today.getTime()) return candidate.getTime() === today.getTime() ? now : noon(candidate);
    }
    month = addMonths(month, -1);
  }
  return now;
}

/// jj/mm ou jj/mm/aaaa (séparateurs / . -). Jamais dans le futur.
function explicitDate(word: string, now: Date): Date | null {
  const parts = word.split(/[/.]/);
  if (parts.length < 2 || parts.length > 3 || !parts.every(p => /^\d+$/.test(p))) return null;
  if (!(parts.length === 3 || word.includes("/"))) return null;
  const day = Number(parts[0]);
  const month = Number(parts[1]);
  if (day < 1 || day > 31 || month < 1 || month > 12) return null;
  const today = startOfDay(now);
  let year = now.getFullYear();
  if (parts.length === 3) {
    if (parts[2].length !== 2 && parts[2].length !== 4) return null;
    year = parts[2].length === 2 ? 2000 + Number(parts[2]) : Number(parts[2]);
  }
  const make = (y: number): Date | null => {
    const d = new Date(2000, 0, 1, 12);
    d.setFullYear(y, month - 1, day);
    return d.getDate() === day && d.getMonth() === month - 1 ? d : null;
  };
  let date = make(year);
  if (!date) return null;
  if (date.getTime() > now.getTime() && parts.length === 2) {
    const previous = make(year - 1);
    if (previous) date = previous;
  }
  if (startOfDay(date).getTime() > today.getTime()) return now;
  return isSameDay(date, now) ? now : date;
}

// MARK: - Analyse du texte

export function parse(input: string, now: Date = new Date()): ExpressEntry {
  const text = collapseOperators(input);
  let tokens = text.split(/\s+/).filter(t => t.length > 0);

  let date = now;
  let amountCents: number | null = null;
  let plusSign = false;
  let amountIndex: number | null = null;
  const consumed = new Set<number>();

  // Dates : mots-clés, jj/mm[/aaaa], « le 5 », jour de semaine.
  let dateFound = false;
  for (let i = 0; i < tokens.length; i++) {
    const word = fold(tokens[i]);
    if (dateFound) continue;
    let explicit: Date | null;
    if (word === "hier") {
      date = shift(now, -1); consumed.add(i); dateFound = true;
    } else if (word === "avant-hier" || word === "avanthier") {
      date = shift(now, -2); consumed.add(i); dateFound = true;
    } else if (word === "avant" && i + 1 < tokens.length && fold(tokens[i + 1]) === "hier") {
      date = shift(now, -2); consumed.add(i); consumed.add(i + 1); dateFound = true;
    } else if (word === "aujourd'hui" || word === "aujourdhui" || word === "auj") {
      consumed.add(i); dateFound = true;
    } else if (Object.hasOwn(weekdays, word)) {
      date = lastWeekday(weekdays[word], now); consumed.add(i); dateFound = true;
    } else if ((explicit = explicitDate(word, now)) !== null) {
      date = explicit; consumed.add(i); dateFound = true;
    } else if (word === "le" && i + 1 < tokens.length) {
      const next = fold(tokens[i + 1]);
      const day = /^[+-]?\d+$/.test(next) ? Number(next) : NaN;
      if (day >= 1 && day <= 31) {
        date = dayOfMonth(day, now); consumed.add(i); consumed.add(i + 1); dateFound = true;
        i++;
      } else if ((explicit = explicitDate(next, now)) !== null) {
        date = explicit; consumed.add(i); consumed.add(i + 1); dateFound = true;
        i++;
      }
    }
  }

  // Montant : premier jeton calculable (nombre ou calcul), « + » en tête = revenu.
  for (let index = 0; index < tokens.length && amountCents === null; index++) {
    if (consumed.has(index)) continue;
    let candidate = tokens[index];
    let plus = false;
    if (candidate.startsWith("+")) { plus = true; candidate = candidate.slice(1); }
    if (!/[0-9]/.test(candidate) || ![...candidate].every(c => "0123456789.,+-−×x*/÷()€".includes(c))) continue;
    const value = evaluate(candidate);
    if (value === null || value <= 0) continue;
    amountCents = value;
    plusSign = plus;
    amountIndex = index;
  }
  if (amountIndex !== null) consumed.add(amountIndex);

  tokens = tokens.filter((_, i) => !consumed.has(i));
  const label = capitalizeFirst(tokens.join(" ").trim());

  const folded = fold(label);
  const words = new Set(folded.split(/[^\p{L}]+/u).filter(w => w.length > 0));
  const isIncome = plusSign || [...words].some(w => incomeWords.has(w)) || incomePhrases.some(p => folded.includes(p));

  return { amountCents, kind: isIncome ? "income" : "expense", date, label };
}

// MARK: - Catégorie

/// Mots-clés par catégorie, dans l'ordre de priorité (« uber eats » avant « uber »).
/// Même liste que StatementCategorizer.swift (sans l'historique, traité à part).
const keywords: { id: string; kind: Kind; words: string[] }[] = [
  { id: "restaurants", kind: "expense", words: ["restaurant", "resto", "mcdo", "mcdonald", "burger king", "kfc", "deliveroo", "uber eats", "just eat", "brasserie", "pizza", "sushi", "starbucks", "boulangerie", "izly", "crous"] },
  { id: "groceries", kind: "expense", words: ["carrefour", "leclerc", "auchan", "lidl", "monoprix", "intermarche", "franprix", "casino", "picard", "aldi", "supermarche", "biocoop", "grand frais"] },
  { id: "transport", kind: "expense", words: ["sncf", "ratp", "navigo", "total", "totalenergies", "esso", "uber", "peage", "bp", "blablacar", "vinci autoroutes", "sanef", "autoroute", "parking", "ouigo", "tisseo"] },
  { id: "housing", kind: "expense", words: ["loyer", "syndic", "edf", "engie", "foncia"] },
  { id: "subscriptions", kind: "expense", words: ["netflix", "spotify", "free", "orange", "sfr", "bouygues", "disney", "canal+", "deezer", "apple.com", "icloud", "youtube", "amazon prime", "sosh", "red by sfr"] },
  { id: "health", kind: "expense", words: ["pharmacie", "medecin", "mutuelle", "docteur", "dentiste", "hopital", "kine", "optique", "laboratoire", "doctolib"] },
  { id: "shopping", kind: "expense", words: ["amazon", "fnac", "decathlon", "zara", "h&m", "ikea", "cdiscount", "darty", "leroy merlin", "zalando", "boulanger"] },
  { id: "salary", kind: "income", words: ["salaire", "virement employeur", "paie"] },
  { id: "refund", kind: "income", words: ["remboursement", "rembt", "cpam", "ameli"] },
];

/// Catégorie d'après les mots-clés courants (étape « b » du categoriseur de relevés), sinon « Autre ».
function suggestByKeywords(label: string, kind: Kind, categories: Category[]): string {
  const isValid = (id: string) => categories.some(c => c.id === id && c.kind === kind && !c.isHidden);
  const normalized = fold(label).split(/\s+/).filter(w => w.length > 0).join(" ");
  const words = normalized.split(/[^\p{L}\p{N}+.&]+/u).filter(w => w.length > 0);
  const padded = ` ${words.join(" ")} `;
  for (const group of keywords) {
    if (group.kind !== kind || !isValid(group.id)) continue;
    for (const keyword of group.words) {
      if (keyword.includes(" ")) {
        if (padded.includes(` ${keyword} `)) return group.id;
      } else if (keyword.length <= 4) {
        if (words.includes(keyword)) return group.id;
      } else if (words.some(w => w.startsWith(keyword))) {
        return group.id;
      }
    }
  }
  return fallbackCategoryID(kind);
}

const splitWords = (text: string) => text.split(/[^\p{L}\p{N}]+/u).filter(w => w.length > 0);

function nameMatches(name: string, words: string[], normalized: string): boolean {
  if (name.length === 0) return false;
  if (normalized === name) return true;
  const nameWords = splitWords(name);
  if (nameWords.length > 1) return ` ${normalized} `.includes(` ${name} `);
  const single = nameWords[0];
  if (single === undefined) return false;
  return words.some(w => w === single || (single.length >= 4 && w.length >= 4 && (w.startsWith(single) || single.startsWith(w))));
}

/// Catégorie devinée : (a) ajout rapide ou nom de catégorie, (b) mots-clés, (c) libellé passé identique, (d) « Autre ».
export function guessCategoryID(label: string, kind: Kind, categories: Category[], quickExpenses: QuickExpense[],
                                transactions: Transaction[]): string {
  const valid = categories.filter(c => c.kind === kind && !c.isHidden);
  const fallback = fallbackCategoryID(kind);
  const normalized = fold(label);
  if (normalized.length === 0) return fallback;
  const words = splitWords(normalized);

  // (a) Nom d'un ajout rapide, puis libellé de catégorie.
  for (const quick of quickExpenses) {
    if (quick.kind === kind && valid.some(c => c.id === quick.categoryID) && nameMatches(fold(quick.name), words, normalized)) {
      return quick.categoryID;
    }
  }
  for (const category of valid) {
    if (nameMatches(fold(category.label), words, normalized)) return category.id;
  }

  // (b) Mots-clés (sans l'historique, traité en (c)).
  const byKeyword = suggestByKeywords(label, kind, categories);
  if (byKeyword !== fallback) return byKeyword;

  // (c) Opération passée au libellé identique.
  let identical: Transaction | null = null;
  for (const t of transactions) {
    if (t.kind === kind && fold(t.note) === normalized && valid.some(c => c.id === t.categoryID)
        && (identical === null || t.date.getTime() >= identical.date.getTime())) identical = t;
  }
  if (identical) return identical.categoryID;

  // (d) « Autre » du type.
  return fallback;
}
