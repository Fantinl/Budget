// Modèle de données : port de Models.swift.
// En mémoire, les montants sont en CENTIMES entiers (champs `…Cents`) et les dates sont des `Date`.
// La conversion vers les fichiers de l'app Mac (euros décimaux, dates ISO 8601 ou secondes depuis 2001)
// se fait uniquement dans codec.ts.

export type Kind = "expense" | "income";

export const kindLabel: Record<Kind, string> = { expense: "Dépense", income: "Revenu" };

/// Identifiant au format de l'app Mac (UUID en majuscules).
export function newID(): string {
  return crypto.randomUUID().toUpperCase();
}

// MARK: - Catégories

export interface Category {
  /// Identifiant stable ; les catégories par défaut gardent « groceries »…
  id: string;
  label: string;
  /// Nom de symbole SF (format de l'app Mac), affiché via `Icon` (src/ui/Icon.svelte).
  icon: string;
  kind: Kind;
  /// Index dans la palette du thème (-1 = couleur de repli).
  colorIndex: number;
  isHidden: boolean;
  /// Budget mensuel par défaut, null = pas de budget.
  monthlyBudgetCents: number | null;
  /// Budgets propres à un mois (clé « 2026-10 »), prioritaires. 0 = pas de budget ce mois-là. null = aucun.
  budgetOverridesCents: Record<string, number> | null;
  /// Report du reste / dépassement des mois précédents de l'année. null = non.
  budgetRollover: boolean | null;
}

function cat(id: string, label: string, icon: string, kind: Kind, colorIndex: number): Category {
  return { id, label, icon, kind, colorIndex, isHidden: false, monthlyBudgetCents: null,
           budgetOverridesCents: null, budgetRollover: null };
}

export const defaultCategories: readonly Category[] = [
  cat("groceries", "Courses", "cart.fill", "expense", 0),
  cat("housing", "Logement", "house.fill", "expense", 1),
  cat("transport", "Transport", "car.fill", "expense", 2),
  cat("restaurants", "Restaurants", "fork.knife", "expense", 3),
  cat("leisure", "Loisirs", "gamecontroller.fill", "expense", 4),
  cat("health", "Santé", "heart.fill", "expense", 5),
  cat("shopping", "Shopping", "bag.fill", "expense", 6),
  cat("subscriptions", "Abonnements", "repeat", "expense", 7),
  cat("otherExpense", "Autre", "ellipsis.circle.fill", "expense", 8),
  cat("salary", "Salaire", "banknote.fill", "income", 9),
  cat("refund", "Remboursement", "arrow.uturn.backward.circle.fill", "income", 10),
  cat("otherIncome", "Autre revenu", "plus.circle.fill", "income", 11),
];

/// Catégorie d'une opération dont la catégorie a été supprimée.
export function unknownCategory(id: string): Category {
  return cat(id, "Sans catégorie", "questionmark.circle", "expense", -1);
}

/// Catégorie « Autre » d'un type : récupère les opérations des catégories supprimées.
export function fallbackCategoryID(kind: Kind): string {
  return kind === "expense" ? "otherExpense" : "otherIncome";
}

/// Réglages de la page Budget.
export interface BudgetPlan {
  savingsGoalCents: number | null;
  expectedIncomeCents: number | null;
}

// MARK: - Opérations

export interface Transaction {
  id: string;
  /// Toujours positif ; le sens vient de `kind`.
  amountCents: number;
  kind: Kind;
  /// Clé JSON « category » (compatibilité avec la première version).
  categoryID: string;
  note: string;
  date: Date;
  /// null = compte principal (`MAIN_ACCOUNT_ID`).
  accountID: string | null;
  /// Créée par une opération récurrente.
  recurringID: string | null;
  /// Virement : deux opérations partagent cet identifiant (dépense sur la source, revenu sur la destination).
  transferID: string | null;
  tagIDs: string[] | null;
  /// Repas Izly décompté automatiquement.
  isAutoMeal: boolean | null;
}

export const isTransfer = (t: Transaction) => t.transferID !== null;
/// Vraie dépense / vrai revenu : les virements ne comptent ni dans l'un ni dans l'autre.
export const isSpending = (t: Transaction) => t.kind === "expense" && t.transferID === null;
export const isEarning = (t: Transaction) => t.kind === "income" && t.transferID === null;
export const resolvedAccountID = (t: { accountID: string | null }) => t.accountID ?? MAIN_ACCOUNT_ID;
/// Négatif pour une dépense.
export const signedCents = (t: { kind: Kind; amountCents: number }) => (t.kind === "expense" ? -t.amountCents : t.amountCents);

export function emptyTransaction(categoryID: string): Transaction {
  return { id: newID(), amountCents: 0, kind: "expense", categoryID, note: "", date: new Date(), accountID: null,
           recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null };
}

// MARK: - Comptes

export type AccountFamily = "current" | "savings" | "investment" | "other";

export const familyLabel: Record<AccountFamily, string> = {
  current: "Comptes courants", savings: "Épargne", investment: "Investissements", other: "Autres",
};
export const families: AccountFamily[] = ["current", "savings", "investment", "other"];

export type AccountKind =
  | "checking"
  | "livretA" | "ldds" | "lep" | "livretJeune" | "pel" | "cel" | "savings" | "assuranceVie"
  | "pea" | "peaPme" | "compteTitres" | "per" | "crypto"
  | "cash" | "card" | "izly";

interface AccountKindInfo { label: string; icon: string; family: AccountFamily; ceilingCents: number | null }

/// Ordre = `AccountKind.allCases`.
export const accountKinds: Record<AccountKind, AccountKindInfo> = {
  checking: { label: "Compte courant", icon: "building.columns.fill", family: "current", ceilingCents: null },
  livretA: { label: "Livret A", icon: "banknote.fill", family: "savings", ceilingCents: 2_295_000 },
  ldds: { label: "LDDS", icon: "banknote.fill", family: "savings", ceilingCents: 1_200_000 },
  lep: { label: "LEP", icon: "banknote.fill", family: "savings", ceilingCents: 1_000_000 },
  livretJeune: { label: "Livret Jeune", icon: "banknote.fill", family: "savings", ceilingCents: 160_000 },
  pel: { label: "PEL", icon: "house.fill", family: "savings", ceilingCents: 6_120_000 },
  cel: { label: "CEL", icon: "house.fill", family: "savings", ceilingCents: 1_530_000 },
  savings: { label: "Compte sur livret", icon: "banknote.fill", family: "savings", ceilingCents: null },
  assuranceVie: { label: "Assurance vie", icon: "shield.fill", family: "savings", ceilingCents: null },
  pea: { label: "PEA", icon: "chart.line.uptrend.xyaxis", family: "investment", ceilingCents: 15_000_000 },
  peaPme: { label: "PEA-PME", icon: "chart.line.uptrend.xyaxis", family: "investment", ceilingCents: 22_500_000 },
  compteTitres: { label: "Compte-titres", icon: "chart.line.uptrend.xyaxis", family: "investment", ceilingCents: null },
  per: { label: "PER", icon: "figure.walk", family: "investment", ceilingCents: null },
  crypto: { label: "Crypto", icon: "bitcoinsign.circle.fill", family: "investment", ceilingCents: null },
  cash: { label: "Espèces", icon: "dollarsign.circle.fill", family: "other", ceilingCents: null },
  card: { label: "Carte prépayée", icon: "creditcard.fill", family: "other", ceilingCents: null },
  izly: { label: "Izly", icon: "fork.knife.circle.fill", family: "other", ceilingCents: null },
};

export const allAccountKinds = Object.keys(accountKinds) as AccountKind[];
export const kindsInFamily = (f: AccountFamily) => allAccountKinds.filter(k => accountKinds[k].family === f);
export const familyOf = (k: AccountKind) => accountKinds[k].family;
/// Placement dont la valeur fluctue : valorisation saisie en plus des versements.
export const hasMarketValue = (k: AccountKind) => accountKinds[k].family === "investment" || k === "assuranceVie";

/// Décompte automatique des repas sur un compte Izly.
export interface MealPlan {
  isEnabled: boolean;
  priceCents: number;
  /// Jours concernés, numérotés comme `Calendar.component(.weekday)` : 1 = dimanche … 7 = samedi.
  weekdays: number[];
  categoryID: string;
  startDate: Date;
  lastGeneratedDate: Date | null;
  lastReviewDate: Date | null;
}

export function defaultMealPlan(now = new Date()): MealPlan {
  return { isEnabled: true, priceCents: DEFAULT_MEAL_PRICE_CENTS, weekdays: [2, 3, 4, 5, 6], categoryID: "restaurants",
           startDate: new Date(now.getFullYear(), now.getMonth(), now.getDate()), lastGeneratedDate: null,
           lastReviewDate: null };
}

export interface Account {
  id: string;
  name: string;
  kind: AccountKind;
  colorIndex: number;
  initialBalanceCents: number;
  isArchived: boolean;
  bank: string | null;
  /// Taux annuel en % (ex. 2.4).
  interestRate: number | null;
  marketValueCents: number | null;
  marketValueDate: Date | null;
  /// null/true = taux réglementé automatique ; false = saisi à la main.
  autoRate: boolean | null;
  openingDate: Date | null;
  mealPlan: MealPlan | null;
}

export const MAIN_ACCOUNT_ID = "main";

export function newAccount(fields: Partial<Account> & Pick<Account, "name" | "kind" | "colorIndex">): Account {
  return { id: newID(), initialBalanceCents: 0, isArchived: false, bank: null, interestRate: null,
           marketValueCents: null, marketValueDate: null, autoRate: null, openingDate: null, mealPlan: null, ...fields };
}

export const mainAccount = (): Account =>
  newAccount({ id: MAIN_ACCOUNT_ID, name: "Compte courant", kind: "checking", colorIndex: 2 });

export const bankLabel = (a: Account) => (a.bank && a.bank.length > 0 ? a.bank : "Sans banque");

// MARK: - Récurrentes

export type Frequency = "weekly" | "monthly" | "quarterly" | "yearly";
export const frequencies: Frequency[] = ["weekly", "monthly", "quarterly", "yearly"];
export const frequencyLabel: Record<Frequency, string> = {
  weekly: "Chaque semaine", monthly: "Chaque mois", quarterly: "Chaque trimestre", yearly: "Chaque année",
};

export interface RecurringOperation {
  id: string;
  name: string;
  amountCents: number;
  kind: Kind;
  categoryID: string;
  /// null = compte par défaut du moment.
  accountID: string | null;
  note: string;
  frequency: Frequency;
  /// Première échéance ; son jour (et son mois pour l'annuel) fixe les suivantes.
  startDate: Date;
  endDate: Date | null;
  isActive: boolean;
  /// Dernière échéance déjà transformée en opération.
  lastGeneratedDate: Date | null;
}

// MARK: - Ajouts rapides

export interface QuickExpense {
  id: string;
  name: string;
  amountCents: number;
  kind: Kind;
  categoryID: string;
  note: string;
  /// null = compte par défaut.
  accountID: string | null;
}

export const defaultQuickExpenses = (): QuickExpense[] => [
  { id: newID(), name: "Café", amountCents: 250, kind: "expense", categoryID: "restaurants", note: "", accountID: null },
  { id: newID(), name: "Boulangerie", amountCents: 300, kind: "expense", categoryID: "groceries", note: "", accountID: null },
  { id: newID(), name: "Essence", amountCents: 6000, kind: "expense", categoryID: "transport", note: "", accountID: null },
];

// MARK: - Tags

export interface Tag {
  id: string;
  name: string;
  colorIndex: number;
}

// MARK: - Profil étudiant

/// Prix d'un repas au restaurant universitaire (1 € pour tous depuis le 4 mai 2026).
export const DEFAULT_MEAL_PRICE_CENTS = 100;
/// Mots repérant une recharge Izly dans un libellé de relevé.
export const IZLY_RECHARGE_KEYWORDS = ["IZLY"];

// MARK: - Ensemble des données

/// Contenu de settings.json.
export interface Settings {
  categories: Category[];
  quickExpenses: QuickExpense[];
  accounts: Account[];
  recurringOperations: RecurringOperation[];
  defaultAccountID: string;
  tags: Tag[];
  budgetPlan: BudgetPlan;
}

export const defaultSettings = (): Settings => ({
  categories: defaultCategories.map(c => ({ ...c })),
  quickExpenses: defaultQuickExpenses(),
  accounts: [mainAccount()],
  recurringOperations: [],
  defaultAccountID: MAIN_ACCOUNT_ID,
  tags: [],
  budgetPlan: { savingsGoalCents: null, expectedIncomeCents: null },
});
