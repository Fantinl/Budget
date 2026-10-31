// Lecture / écriture au format JSON de l'app Mac (JSONEncoder Swift).
// - Fichiers locaux (transactions.json, settings.json, sauvegardes) : dates ISO 8601 sans fractions de seconde.
// - Fichier de synchro et sync-meta.json : dates en secondes depuis le 1er janvier 2001 (stratégie par défaut).
// La lecture accepte les deux. Les montants (Decimal) sont des nombres en euros. Les optionnels nil sont omis.

import {
  type Account, type AccountKind, type BudgetPlan, type Category, type Frequency, type Kind, type MealPlan,
  type QuickExpense, type RecurringOperation, type Settings, type Tag, type Transaction,
  accountKinds, defaultSettings, DEFAULT_MEAL_PRICE_CENTS, MAIN_ACCOUNT_ID,
} from "./model";

export type Obj = Record<string, unknown>;
export type DateFormat = "iso" | "reference";

/// Secondes entre 1970 et le 1er janvier 2001 (date de référence d'Apple).
const APPLE_EPOCH = 978307200;

// MARK: - Valeurs simples

export function decodeDate(v: unknown): Date {
  if (typeof v === "number") return new Date((v + APPLE_EPOCH) * 1000);
  if (typeof v === "string") return new Date(v);
  return new Date(NaN);
}

const dateOrNull = (v: unknown): Date | null => (v === null || v === undefined ? null : decodeDate(v));

export function encodeDate(d: Date, format: DateFormat): string | number {
  if (format === "reference") return (d.getTime() - APPLE_EPOCH * 1000) / 1000;   // soustraction d'abord : pas de bruit flottant
  // Swift `.iso8601` n'accepte pas les millisecondes.
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}

/// Euros (nombre JSON) → centimes entiers.
export const toCents = (v: unknown): number => (typeof v === "number" ? Math.round(v * 100) : 0);
const centsOrNull = (v: unknown): number | null => (typeof v === "number" ? Math.round(v * 100) : null);
/// Centimes → euros pour l'écriture (125 → 1.25).
export const fromCents = (c: number): number => Math.round(c) / 100;

const str = (v: unknown, fallback = ""): string => (typeof v === "string" ? v : fallback);
const strOrNull = (v: unknown): string | null => (typeof v === "string" ? v : null);
const num = (v: unknown, fallback = 0): number => (typeof v === "number" ? v : fallback);
const numOrNull = (v: unknown): number | null => (typeof v === "number" ? v : null);
const boolOrNull = (v: unknown): boolean | null => (typeof v === "boolean" ? v : null);
const kind = (v: unknown): Kind => (v === "income" ? "income" : "expense");
export const objects = (v: unknown): Obj[] => (Array.isArray(v) ? v.filter(x => x && typeof x === "object") as Obj[] : []);

/// Ajoute la clé seulement si la valeur n'est pas nulle (optionnel Swift).
function put(o: Obj, key: string, value: unknown) {
  if (value !== null && value !== undefined) o[key] = value;
}

// MARK: - Enregistrements

export function decodeTransaction(o: Obj): Transaction {
  return {
    id: str(o.id).toUpperCase(),
    amountCents: toCents(o.amount),
    kind: kind(o.kind),
    categoryID: str(o.category),
    note: str(o.note),
    date: decodeDate(o.date),
    accountID: strOrNull(o.accountID),
    recurringID: strOrNull(o.recurringID)?.toUpperCase() ?? null,
    transferID: strOrNull(o.transferID)?.toUpperCase() ?? null,
    tagIDs: Array.isArray(o.tagIDs) ? (o.tagIDs as unknown[]).filter((x): x is string => typeof x === "string") : null,
    isAutoMeal: boolOrNull(o.isAutoMeal),
  };
}

export function encodeTransaction(t: Transaction, f: DateFormat): Obj {
  const o: Obj = { id: t.id, amount: fromCents(t.amountCents), kind: t.kind, category: t.categoryID, note: t.note,
                   date: encodeDate(t.date, f) };
  put(o, "accountID", t.accountID);
  put(o, "recurringID", t.recurringID);
  put(o, "transferID", t.transferID);
  put(o, "tagIDs", t.tagIDs);
  put(o, "isAutoMeal", t.isAutoMeal);
  return o;
}

export function decodeCategory(o: Obj): Category {
  let overrides: Record<string, number> | null = null;
  if (o.budgetOverrides && typeof o.budgetOverrides === "object") {
    overrides = {};
    for (const [k, v] of Object.entries(o.budgetOverrides as Obj)) overrides[k] = toCents(v);
  }
  return {
    id: str(o.id), label: str(o.label), icon: str(o.icon, "questionmark.circle"), kind: kind(o.kind),
    colorIndex: num(o.colorIndex), isHidden: o.isHidden === true, monthlyBudgetCents: centsOrNull(o.monthlyBudget),
    budgetOverridesCents: overrides, budgetRollover: boolOrNull(o.budgetRollover),
  };
}

export function encodeCategory(c: Category): Obj {
  const o: Obj = { id: c.id, label: c.label, icon: c.icon, kind: c.kind, colorIndex: c.colorIndex, isHidden: c.isHidden };
  put(o, "monthlyBudget", c.monthlyBudgetCents === null ? null : fromCents(c.monthlyBudgetCents));
  if (c.budgetOverridesCents) {
    const overrides: Obj = {};
    for (const k of Object.keys(c.budgetOverridesCents).sort()) overrides[k] = fromCents(c.budgetOverridesCents[k]);
    o.budgetOverrides = overrides;
  }
  put(o, "budgetRollover", c.budgetRollover);
  return o;
}

function decodeMealPlan(o: Obj): MealPlan {
  const weekdays = Array.isArray(o.weekdays) ? (o.weekdays as unknown[]).filter((x): x is number => typeof x === "number") : [2, 3, 4, 5, 6];
  return {
    isEnabled: o.isEnabled !== false,
    priceCents: typeof o.price === "number" ? toCents(o.price) : DEFAULT_MEAL_PRICE_CENTS,
    weekdays: [...new Set(weekdays)].sort((a, b) => a - b),
    categoryID: str(o.categoryID, "restaurants"),
    startDate: o.startDate === undefined ? new Date() : decodeDate(o.startDate),
    lastGeneratedDate: dateOrNull(o.lastGeneratedDate),
    lastReviewDate: dateOrNull(o.lastReviewDate),
  };
}

function encodeMealPlan(m: MealPlan, f: DateFormat): Obj {
  const o: Obj = { isEnabled: m.isEnabled, price: fromCents(m.priceCents), weekdays: [...m.weekdays].sort((a, b) => a - b),
                   categoryID: m.categoryID, startDate: encodeDate(m.startDate, f) };
  put(o, "lastGeneratedDate", m.lastGeneratedDate && encodeDate(m.lastGeneratedDate, f));
  put(o, "lastReviewDate", m.lastReviewDate && encodeDate(m.lastReviewDate, f));
  return o;
}

export function decodeAccount(o: Obj): Account {
  // Type inconnu (fichier d'une version future) → compte courant.
  const k = typeof o.kind === "string" && o.kind in accountKinds ? (o.kind as AccountKind) : "checking";
  return {
    id: str(o.id), name: str(o.name), kind: k, colorIndex: num(o.colorIndex), initialBalanceCents: toCents(o.initialBalance),
    isArchived: o.isArchived === true, bank: strOrNull(o.bank), interestRate: numOrNull(o.interestRate),
    marketValueCents: centsOrNull(o.marketValue), marketValueDate: dateOrNull(o.marketValueDate),
    autoRate: boolOrNull(o.autoRate), openingDate: dateOrNull(o.openingDate),
    mealPlan: o.mealPlan && typeof o.mealPlan === "object" ? decodeMealPlan(o.mealPlan as Obj) : null,
  };
}

export function encodeAccount(a: Account, f: DateFormat): Obj {
  const o: Obj = { id: a.id, name: a.name, kind: a.kind, colorIndex: a.colorIndex,
                   initialBalance: fromCents(a.initialBalanceCents), isArchived: a.isArchived };
  put(o, "bank", a.bank);
  put(o, "interestRate", a.interestRate);
  put(o, "marketValue", a.marketValueCents === null ? null : fromCents(a.marketValueCents));
  put(o, "marketValueDate", a.marketValueDate && encodeDate(a.marketValueDate, f));
  put(o, "autoRate", a.autoRate);
  put(o, "openingDate", a.openingDate && encodeDate(a.openingDate, f));
  put(o, "mealPlan", a.mealPlan && encodeMealPlan(a.mealPlan, f));
  return o;
}

const FREQUENCIES: Frequency[] = ["weekly", "monthly", "quarterly", "yearly"];

export function decodeRecurring(o: Obj): RecurringOperation {
  return {
    id: str(o.id).toUpperCase(), name: str(o.name), amountCents: toCents(o.amount), kind: kind(o.kind),
    categoryID: str(o.categoryID), accountID: strOrNull(o.accountID), note: str(o.note),
    frequency: FREQUENCIES.includes(o.frequency as Frequency) ? (o.frequency as Frequency) : "monthly",
    startDate: decodeDate(o.startDate), endDate: dateOrNull(o.endDate), isActive: o.isActive !== false,
    lastGeneratedDate: dateOrNull(o.lastGeneratedDate),
  };
}

export function encodeRecurring(r: RecurringOperation, f: DateFormat): Obj {
  const o: Obj = { id: r.id, name: r.name, amount: fromCents(r.amountCents), kind: r.kind, categoryID: r.categoryID,
                   note: r.note, frequency: r.frequency, startDate: encodeDate(r.startDate, f), isActive: r.isActive };
  put(o, "accountID", r.accountID);
  put(o, "endDate", r.endDate && encodeDate(r.endDate, f));
  put(o, "lastGeneratedDate", r.lastGeneratedDate && encodeDate(r.lastGeneratedDate, f));
  return o;
}

export function decodeQuickExpense(o: Obj): QuickExpense {
  return { id: str(o.id).toUpperCase(), name: str(o.name), amountCents: toCents(o.amount), kind: kind(o.kind),
           categoryID: str(o.categoryID), note: str(o.note), accountID: strOrNull(o.accountID) };
}

export function encodeQuickExpense(q: QuickExpense): Obj {
  const o: Obj = { id: q.id, name: q.name, amount: fromCents(q.amountCents), kind: q.kind, categoryID: q.categoryID, note: q.note };
  put(o, "accountID", q.accountID);
  return o;
}

export const decodeTag = (o: Obj): Tag => ({ id: str(o.id), name: str(o.name), colorIndex: num(o.colorIndex) });
export const encodeTag = (t: Tag): Obj => ({ id: t.id, name: t.name, colorIndex: t.colorIndex });

export function decodeBudgetPlan(v: unknown): BudgetPlan {
  const o = v && typeof v === "object" ? (v as Obj) : {};
  return { savingsGoalCents: centsOrNull(o.savingsGoal), expectedIncomeCents: centsOrNull(o.expectedIncome) };
}

export function encodeBudgetPlan(p: BudgetPlan): Obj {
  const o: Obj = {};
  put(o, "savingsGoal", p.savingsGoalCents === null ? null : fromCents(p.savingsGoalCents));
  put(o, "expectedIncome", p.expectedIncomeCents === null ? null : fromCents(p.expectedIncomeCents));
  return o;
}

// MARK: - Fichiers

/// settings.json : clés absentes → valeurs par défaut (comme `Settings.init(from:)`).
export function decodeSettings(o: Obj): Settings {
  const d = defaultSettings();
  return {
    categories: Array.isArray(o.categories) ? objects(o.categories).map(decodeCategory) : d.categories,
    quickExpenses: Array.isArray(o.quickExpenses) ? objects(o.quickExpenses).map(decodeQuickExpense) : d.quickExpenses,
    accounts: Array.isArray(o.accounts) ? objects(o.accounts).map(decodeAccount) : d.accounts,
    recurringOperations: Array.isArray(o.recurringOperations) ? objects(o.recurringOperations).map(decodeRecurring) : [],
    defaultAccountID: str(o.defaultAccountID, MAIN_ACCOUNT_ID),
    tags: Array.isArray(o.tags) ? objects(o.tags).map(decodeTag) : [],
    budgetPlan: decodeBudgetPlan(o.budgetPlan),
  };
}

export function encodeSettings(s: Settings, f: DateFormat = "iso"): Obj {
  return {
    accounts: s.accounts.map(a => encodeAccount(a, f)),
    budgetPlan: encodeBudgetPlan(s.budgetPlan),
    categories: s.categories.map(encodeCategory),
    defaultAccountID: s.defaultAccountID,
    quickExpenses: s.quickExpenses.map(encodeQuickExpense),
    recurringOperations: s.recurringOperations.map(r => encodeRecurring(r, f)),
    tags: s.tags.map(encodeTag),
  };
}

export const decodeTransactions = (v: unknown): Transaction[] => objects(v).map(decodeTransaction);
export const encodeTransactions = (ts: Transaction[], f: DateFormat = "iso"): Obj[] => ts.map(t => encodeTransaction(t, f));

/// JSON trié par clés et indenté, comme `JSONEncoder` avec `.prettyPrinted, .sortedKeys`.
export function prettyJSON(value: unknown): string {
  return JSON.stringify(sortKeys(value), null, 2);
}

/// JSON compact trié par clés (fichier de synchro, comparaisons).
export function compactJSON(value: unknown): string {
  return JSON.stringify(sortKeys(value));
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object" && !(value instanceof Date)) {
    const out: Obj = {};
    for (const k of Object.keys(value as Obj).sort()) out[k] = sortKeys((value as Obj)[k]);
    return out;
  }
  return value;
}
