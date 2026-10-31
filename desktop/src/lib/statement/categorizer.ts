// Propose une catégorie pour chaque ligne d'un relevé : port de StatementCategorizer.swift.

import { type Category, type Kind, type Transaction, fallbackCategoryID } from "../model";
import { normalize } from "./text";

const STOP_WORDS = new Set([
  "cb", "carte", "prlv", "prelevement", "vir", "virement", "paiement", "achat", "sepa",
  "par", "de", "du", "des", "the", "inst", "sct", "remise", "retrait",
]);

/// Mots-clés par catégorie, dans l'ordre de priorité (« uber eats » avant « uber »).
const KEYWORDS: { id: string; kind: Kind; words: string[] }[] = [
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

/// Mots significatifs d'un libellé : sans accents, sans chiffres ni mots bancaires génériques.
function tokens(text: string): Set<string> {
  return new Set(normalize(text).split(/[^\p{L}]+/u).filter(w => [...w].length >= 3 && !STOP_WORDS.has(w)));
}

export class StatementCategorizer {
  /// Opérations existantes : mots-clés du libellé → catégorie la plus fréquente.
  private known: { tokens: Set<string>; categoryID: string }[] = [];

  constructor(private readonly categories: readonly Category[], transactions: readonly Transaction[]) {
    // Catégorie la plus fréquente pour chaque libellé distinct (catégories encore existantes seulement).
    const ids = new Set(categories.map(c => c.id));
    const counts = new Map<string, { tokens: Set<string>; byCategory: Map<string, number> }>();
    for (const t of transactions) {
      if (t.note.length === 0 || !ids.has(t.categoryID)) continue;
      const set = tokens(t.note);
      if (set.size === 0) continue;
      const key = [...set].sort().join("\u0000");
      let entry = counts.get(key);
      if (!entry) { entry = { tokens: set, byCategory: new Map() }; counts.set(key, entry); }
      entry.byCategory.set(t.categoryID, (entry.byCategory.get(t.categoryID) ?? 0) + 1);
    }
    for (const { tokens: set, byCategory } of counts.values()) {
      let best: [string, number] | null = null;
      for (const [id, n] of byCategory) if (!best || n > best[1]) best = [id, n];
      if (best) this.known.push({ tokens: set, categoryID: best[0] });
    }
  }

  /// Catégorie proposée pour un libellé et un type d'opération.
  suggest(label: string, kind: Kind): string {
    const set = tokens(label);

    // (a) Libellé très proche d'une opération existante du même type.
    let bestMatch: { id: string; score: number } | null = null;
    for (const entry of this.known) {
      if (!this.isValid(entry.categoryID, kind) || set.size === 0) continue;
      let common = 0;
      for (const w of set) if (entry.tokens.has(w)) common++;
      if (common === 0) continue;
      const score = common / (set.size + entry.tokens.size - common);
      if (score >= 0.7 && score > (bestMatch?.score ?? 0)) bestMatch = { id: entry.categoryID, score };
    }
    if (bestMatch) return bestMatch.id;

    // (b) Mots-clés courants.
    const words = normalize(label).split(/[^\p{L}\p{N}+.&]+/u).filter(w => w.length > 0);
    const padded = " " + words.join(" ") + " ";
    for (const group of KEYWORDS) {
      if (group.kind !== kind || !this.isValid(group.id, kind)) continue;
      for (const keyword of group.words) {
        if (keyword.includes(" ")) {
          if (padded.includes(` ${keyword} `)) return group.id;
        } else if ([...keyword].length <= 4) {
          if (words.includes(keyword)) return group.id;
        } else if (words.some(w => w.startsWith(keyword))) {
          return group.id;
        }
      }
    }

    // (c) « Autre » du bon type.
    return fallbackCategoryID(kind);
  }

  private isValid(id: string, kind: Kind): boolean {
    return this.categories.some(c => c.id === id && c.kind === kind && !c.isHidden);
  }
}
