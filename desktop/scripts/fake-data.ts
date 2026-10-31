// Génère une base fictive (transactions.json + settings.json au format de l'app Mac) pour les essais et les mesures.
// Usage : npx vite-node scripts/fake-data.ts <dossier> [nombre d'opérations, 1500 par défaut]
// Les données sont déterministes (même graine → mêmes données) et se terminent aujourd'hui.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { encodeSettings, encodeTransactions, prettyJSON } from "../src/lib/codec";
import {
  type Account, type Category, type QuickExpense, type RecurringOperation, type Tag, type Transaction,
  defaultCategories, defaultMealPlan, MAIN_ACCOUNT_ID, newAccount,
} from "../src/lib/model";

const [, , outDir, countArg] = process.argv;
if (!outDir) { console.error("Usage : fake-data.ts <dossier> [nombre]"); process.exit(1); }
const target = Number(countArg ?? 1500);

// Générateur pseudo-aléatoire (mulberry32) et identifiants reproductibles.
let seed = 20261031;
const random = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = <T>(items: readonly T[]) => items[Math.floor(random() * items.length)];
const between = (min: number, max: number) => Math.round((min + random() * (max - min)) * 100);
let counter = 0;
const id = () => {
  const hex = (counter++).toString(16).padStart(12, "0") + Math.floor(random() * 0xffffffff).toString(16).padStart(8, "0");
  return `FA4E0000-0000-4000-8000-${hex.slice(-12)}`.toUpperCase();
};

const now = new Date();
const day = (d: Date, hour = 12) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), hour, Math.floor(random() * 60));

// Comptes
const izly = newAccount({ id: id(), name: "Izly", kind: "izly", colorIndex: 3, mealPlan: { ...defaultMealPlan(now), lastGeneratedDate: day(now, 0), lastReviewDate: day(now, 0) } });
const accounts: Account[] = [
  newAccount({ id: MAIN_ACCOUNT_ID, name: "Compte courant", kind: "checking", colorIndex: 2, initialBalanceCents: 120_000, bank: "Banque Exemple" }),
  newAccount({ id: id(), name: "Livret A", kind: "livretA", colorIndex: 0, initialBalanceCents: 350_000, bank: "Banque Exemple", interestRate: 2.4 }),
  newAccount({ id: id(), name: "PEA", kind: "pea", colorIndex: 4, initialBalanceCents: 200_000, bank: "Courtier Exemple", marketValueCents: 0, marketValueDate: now }),
  izly,
];
const [checking, livret, pea] = accounts;

// Catégories : celles par défaut, avec des budgets (un report, un budget propre au mois courant).
const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
const budgets: Record<string, number> = { groceries: 32_000, restaurants: 12_000, leisure: 8_000, transport: 9_000, shopping: 10_000 };
const categories: Category[] = defaultCategories.map(c => ({
  ...c,
  monthlyBudgetCents: budgets[c.id] ?? null,
  budgetRollover: c.id === "restaurants" ? true : null,
  budgetOverridesCents: c.id === "leisure" ? { [monthKey]: 15_000 } : null,
}));

const tags: Tag[] = [
  { id: id(), name: "vacances", colorIndex: 9 },
  { id: id(), name: "remboursable", colorIndex: 5 },
  { id: id(), name: "cadeau", colorIndex: 6 },
];

const quickExpenses: QuickExpense[] = [
  { id: id(), name: "Café", amountCents: 250, kind: "expense", categoryID: "restaurants", note: "", accountID: null },
  { id: id(), name: "Boulangerie", amountCents: 300, kind: "expense", categoryID: "groceries", note: "", accountID: null },
  { id: id(), name: "Ticket de métro", amountCents: 215, kind: "expense", categoryID: "transport", note: "", accountID: null },
];

// Durée couverte : ~2,6 opérations par jour (courantes, récurrentes, repas), sur 10 ans au plus ;
// au-delà, les journées sont plus chargées.
const days = Math.min(3650, Math.max(60, Math.round(target / 2.6)));
const density = Math.max(1, target / (days * 2.6));
const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - days);

const recurring = (name: string, cents: number, kind: "expense" | "income", categoryID: string, dayOfMonth: number): RecurringOperation => ({
  id: id(), name, amountCents: cents, kind, categoryID, accountID: null, note: "", frequency: "monthly",
  startDate: new Date(start.getFullYear(), start.getMonth(), dayOfMonth), endDate: null, isActive: true, lastGeneratedDate: null,
});
const recurringOperations = [
  recurring("Salaire", 210_000, "income", "salary", 28),
  recurring("Loyer", 72_000, "expense", "housing", 5),
  recurring("Électricité", 5_500, "expense", "housing", 12),
  recurring("Internet / box", 2_999, "expense", "subscriptions", 8),
  recurring("Forfait mobile", 999, "expense", "subscriptions", 15),
  recurring("Streaming", 1_349, "expense", "subscriptions", 20),
];

const transactions: Transaction[] = [];
const add = (t: Partial<Transaction> & Pick<Transaction, "amountCents" | "kind" | "categoryID" | "date">) =>
  transactions.push({ id: id(), note: "", accountID: null, recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null, ...t });

const daily = [
  { cat: "groceries", notes: ["Supermarché", "Marché", "Épicerie", "Boulangerie"], min: 3, max: 85, weight: 5 },
  { cat: "restaurants", notes: ["Café", "Déjeuner", "Pizza", "Kebab", "Restaurant"], min: 2.5, max: 45, weight: 4 },
  { cat: "transport", notes: ["Métro", "Essence", "Train", "Vélo"], min: 2, max: 70, weight: 2 },
  { cat: "leisure", notes: ["Cinéma", "Concert", "Livre", "Jeu vidéo", "Sport"], min: 8, max: 60, weight: 1.5 },
  { cat: "shopping", notes: ["Vêtements", "Chaussures", "Maison", "High-tech"], min: 10, max: 150, weight: 1 },
  { cat: "health", notes: ["Pharmacie", "Médecin", "Dentiste"], min: 5, max: 60, weight: 0.4 },
  { cat: "otherExpense", notes: ["Divers", "Coiffeur", "Cadeau"], min: 5, max: 50, weight: 0.5 },
];
const totalWeight = daily.reduce((s, d) => s + d.weight, 0);

for (let d = new Date(start); d <= now; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
  // Récurrentes du jour (créées comme le fait l'app à chaque échéance)
  for (const r of recurringOperations) {
    if (d.getDate() === r.startDate.getDate()) {
      add({ amountCents: r.amountCents, kind: r.kind, categoryID: r.categoryID, note: r.name, date: day(d, 0), recurringID: r.id });
      r.lastGeneratedDate = day(d, 0);
    }
  }
  // Dépenses courantes : 0 à 4 par jour
  const n = Math.floor(random() * 4.2 * density + (density - 1) * 1.6);
  for (let i = 0; i < n; i++) {
    let x = random() * totalWeight;
    const kind = daily.find(k => (x -= k.weight) < 0) ?? daily[0];
    const tagIDs = random() < 0.05 ? [pick(tags).id] : null;
    add({ amountCents: between(kind.min, kind.max), kind: "expense", categoryID: kind.cat, note: pick(kind.notes), date: day(d, 8 + Math.floor(random() * 13)), tagIDs });
  }
  // Repas Izly en semaine (décomptés automatiquement) et recharge le 1er
  const weekday = d.getDay();
  if (weekday >= 1 && weekday <= 5 && random() < 0.8) {
    add({ amountCents: 100, kind: "expense", categoryID: "restaurants", note: "Repas Crous", date: day(d, 0), accountID: izly.id, isAutoMeal: true });
  }
  if (d.getDate() === 1) {
    const transferID = id();
    add({ amountCents: 2_000, kind: "expense", categoryID: "otherExpense", note: "Recharge Izly", date: day(d, 9), transferID });
    add({ amountCents: 2_000, kind: "income", categoryID: "otherIncome", note: "Recharge Izly", date: day(d, 9), transferID, accountID: izly.id });
  }
  // Épargne : virement vers le Livret A le 29, versement PEA le 10
  if (d.getDate() === 29) {
    const transferID = id();
    add({ amountCents: 30_000, kind: "expense", categoryID: "otherExpense", note: "Épargne", date: day(d, 10), transferID });
    add({ amountCents: 30_000, kind: "income", categoryID: "otherIncome", note: "Épargne", date: day(d, 10), transferID, accountID: livret.id });
  }
  if (d.getDate() === 10) {
    const transferID = id();
    add({ amountCents: 15_000, kind: "expense", categoryID: "otherExpense", note: "Versement PEA", date: day(d, 10), transferID });
    add({ amountCents: 15_000, kind: "income", categoryID: "otherIncome", note: "Versement PEA", date: day(d, 10), transferID, accountID: pea.id });
  }
  // Remboursements occasionnels
  if (random() < 0.02) add({ amountCents: between(10, 80), kind: "income", categoryID: "refund", note: "Remboursement", date: day(d, 14) });
}
// Valorisation du PEA : versements + 8 %
const peaDeposits = transactions.filter(t => t.accountID === pea.id).reduce((s, t) => s + t.amountCents, pea.initialBalanceCents);
accounts[2] = { ...pea, marketValueCents: Math.round(peaDeposits * 1.08) };
void checking;

mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, "transactions.json"), prettyJSON(encodeTransactions(transactions)));
writeFileSync(join(outDir, "settings.json"), prettyJSON(encodeSettings({
  categories, quickExpenses, accounts, recurringOperations, defaultAccountID: MAIN_ACCOUNT_ID, tags,
  budgetPlan: { savingsGoalCents: 30_000, expectedIncomeCents: null },
})));
console.log(`${transactions.length} opérations sur ${days} jours → ${outDir}`);
