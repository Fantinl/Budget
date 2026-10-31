// Magasin des données : port de BudgetStore.swift (+ Undo, + pont de synchro).
//
// Règles pour tout le code qui modifie les données (port des extensions `BudgetStore+X.swift`) :
// - les tableaux sont en `$state.raw` : on ne les modifie JAMAIS en place, on les remplace
//   (`s.transactions = s.transactions.map(...)`, `s.categories = [...s.categories, c]`) ;
// - les enregistrements sont traités comme immuables : on remplace l'objet (`{ ...t, note }`) ;
// - toute action de l'utilisateur commence par `s.registerUndo("Libellé")` puis se termine par
//   `s.saveTransactions()` et/ou `s.saveSettings()` (comme en Swift) ; la synchro est suivie automatiquement.
// Les fonctions des extensions vivent dans src/lib/logic/*.ts et prennent le magasin en premier argument.

import {
  type Account, type BudgetPlan, type Category, type Kind, type QuickExpense, type RecurringOperation, type Settings,
  type Tag, type Transaction, defaultCategories, defaultMealPlan, defaultSettings, fallbackCategoryID, MAIN_ACCOUNT_ID,
  mainAccount, unknownCategory,
} from "./model";
import { isInMonth } from "./dates";
import { type Obj, decodeSettings, decodeTransactions, encodeSettings, encodeTransactions, prettyJSON, compactJSON } from "./codec";
import { fileInfo, join, readText, renamePath, writeText } from "./platform";
import { SyncTracker, decodeMeta, encodeMeta } from "./sync/tracker";

interface Snapshot {
  transactions: Transaction[];
  categories: Category[];
  quickExpenses: QuickExpense[];
  accounts: Account[];
  recurringOperations: RecurringOperation[];
  defaultAccountID: string;
  tags: Tag[];
  budgetPlan: BudgetPlan;
}

interface UndoEntry { name: string; snapshot: Snapshot }

export class BudgetStore {
  transactions = $state.raw<Transaction[]>([]);
  categories = $state.raw<Category[]>(defaultCategories.map(c => ({ ...c })));
  /// Objectif d'épargne et revenus prévus (page Budget).
  budgetPlan = $state.raw<BudgetPlan>({ savingsGoalCents: null, expectedIncomeCents: null });
  quickExpenses = $state.raw<QuickExpense[]>(defaultSettings().quickExpenses);
  accounts = $state.raw<Account[]>([mainAccount()]);
  recurringOperations = $state.raw<RecurringOperation[]>([]);
  tags = $state.raw<Tag[]>([]);
  /// Compte proposé par défaut pour les nouvelles opérations. Voir `defaultAccount`.
  defaultAccountID = $state(MAIN_ACCOUNT_ID);
  /// Message d'erreur à afficher (enregistrement impossible, fichier illisible…).
  errorMessage = $state<string | null>(null);

  /// Suivi des modifications pour la synchronisation.
  readonly sync = new SyncTracker();

  // Annuler / Rétablir
  private undoStack = $state.raw<UndoEntry[]>([]);
  private redoStack = $state.raw<UndoEntry[]>([]);
  private undoGroupOpen = false;

  /// Index des catégories par identifiant (recalculé quand la liste change).
  private categoryIndex = $derived(new Map(this.categories.map(c => [c.id, c])));

  constructor(readonly directory: string) {}

  get transactionsPath() { return join(this.directory, "transactions.json"); }
  get settingsPath() { return join(this.directory, "settings.json"); }
  get syncMetaPath() { return join(this.directory, "sync-meta.json"); }

  // MARK: - Chargement

  /// (Re)lit les fichiers. Utilisé au lancement et après une restauration de sauvegarde.
  async reloadFromDisk(): Promise<void> {
    const transactions = await this.load(this.transactionsPath, v => (Array.isArray(v) ? decodeTransactions(v) : null));
    const settings = await this.load(this.settingsPath, v => (v && typeof v === "object" ? decodeSettings(v as Obj) : null));
    this.applySettings(settings ?? defaultSettings());
    this.transactions = transactions ?? [];
    // Comptes Izly créés avant le décompte automatique : un repas par jour (lun→ven) à partir d'aujourd'hui.
    if (this.accounts.some(a => a.kind === "izly" && !a.mealPlan)) {
      this.accounts = this.accounts.map(a => (a.kind === "izly" && !a.mealPlan ? { ...a, mealPlan: defaultMealPlan() } : a));
    }
    this.ensureRequiredRecords();
    const metaText = this.sync.baseline === null ? await readText(this.syncMetaPath).catch(() => null) : null;
    let meta = null;
    if (metaText) { try { meta = decodeMeta(JSON.parse(metaText)); } catch { meta = null; } }
    const modified = async (p: string) => { const i = await fileInfo(p); return i ? new Date(i.modifiedMs) : null; };
    this.sync.didReload(this, meta, { transactions: await modified(this.transactionsPath), settings: await modified(this.settingsPath) });
  }

  private applySettings(s: Settings) {
    this.categories = s.categories;
    this.quickExpenses = s.quickExpenses;
    this.accounts = s.accounts;
    this.recurringOperations = s.recurringOperations;
    this.tags = s.tags;
    this.budgetPlan = s.budgetPlan;
    this.defaultAccountID = s.defaultAccountID;
  }

  /// Lit un fichier JSON ; s'il est illisible, il est mis de côté plutôt qu'écrasé à la prochaine sauvegarde.
  private async load<T>(path: string, decode: (v: unknown) => T | null): Promise<T | null> {
    const text = await readText(path);
    if (text === null) return null;
    try {
      const value = decode(JSON.parse(text));
      if (value === null) throw new Error("format inattendu");
      return value;
    } catch {
      const backup = path.replace(/\.json$/, `.illisible-${Math.floor(Date.now() / 1000)}.json`);
      await renamePath(path, backup).catch(() => {});
      this.errorMessage = `Le fichier ${path.split(/[\\/]/).pop()} n'a pas pu être lu. Une copie a été gardée : ${backup.split(/[\\/]/).pop()}`;
      return null;
    }
  }

  /// Le compte principal et les catégories « Autre » doivent toujours exister.
  ensureRequiredRecords() {
    if (!this.accounts.some(a => a.id === MAIN_ACCOUNT_ID)) this.accounts = [mainAccount(), ...this.accounts];
    for (const kind of ["expense", "income"] as Kind[]) {
      const id = fallbackCategoryID(kind);
      if (!this.categories.some(c => c.id === id)) {
        const fallback = defaultCategories.find(c => c.id === id);
        if (fallback) this.categories = [...this.categories, { ...fallback }];
      }
    }
  }

  // MARK: - Enregistrement

  private writes = new Map<string, string>();
  private writeChain: Promise<void> = Promise.resolve();

  /// Écrit un fichier ; les écritures sont faites dans l'ordre, et seule la dernière version en attente est écrite.
  writeFile(path: string, contents: string): Promise<void> {
    const pending = this.writes.has(path);
    this.writes.set(path, contents);
    if (pending) return this.writeChain;
    this.writeChain = this.writeChain.then(async () => {
      const latest = this.writes.get(path);
      this.writes.delete(path);
      if (latest === undefined) return;
      try { await writeText(path, latest); }
      catch (e) { this.errorMessage = `Échec de l'enregistrement : ${e instanceof Error ? e.message : String(e)}`; }
    });
    return this.writeChain;
  }

  /// Attend la fin des écritures en cours (avant une sauvegarde, une synchro, la fermeture…).
  flush(): Promise<void> { return this.writeChain; }

  saveTransactions() {
    void this.writeFile(this.transactionsPath, prettyJSON(encodeTransactions(this.transactions)));
    this.sync.trackTransactions(this);
  }

  saveSettings() {
    void this.writeFile(this.settingsPath, prettyJSON(encodeSettings(this.currentSettings())));
    this.sync.trackSettings(this);
  }

  persistSyncMeta(): Promise<void> {
    return this.writeFile(this.syncMetaPath, compactJSON(encodeMeta(this.sync.meta)));
  }

  currentSettings(): Settings {
    return { categories: this.categories, quickExpenses: this.quickExpenses, accounts: this.accounts,
             recurringOperations: this.recurringOperations, defaultAccountID: this.defaultAccountID, tags: this.tags,
             budgetPlan: this.budgetPlan };
  }

  // MARK: - Annuler / Rétablir

  private snapshot(): Snapshot {
    return { transactions: this.transactions, categories: this.categories, quickExpenses: this.quickExpenses,
             accounts: this.accounts, recurringOperations: this.recurringOperations, defaultAccountID: this.defaultAccountID,
             tags: this.tags, budgetPlan: this.budgetPlan };
  }

  /// À appeler au début de toute modification faite par l'utilisateur.
  /// Plusieurs appels dans une même action (même tâche JavaScript) forment une seule étape d'annulation.
  registerUndo(name: string) {
    if (this.undoGroupOpen) return;
    this.undoGroupOpen = true;
    queueMicrotask(() => { this.undoGroupOpen = false; });
    this.undoStack = [...this.undoStack.slice(-99), { name, snapshot: this.snapshot() }];
    this.redoStack = [];
  }

  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }
  /// « Annuler Supprimer l'opération »
  get undoActionName() { return this.undoStack.at(-1)?.name ?? null; }
  get redoActionName() { return this.redoStack.at(-1)?.name ?? null; }

  undo() {
    const entry = this.undoStack.at(-1);
    if (!entry) return;
    this.undoStack = this.undoStack.slice(0, -1);
    this.redoStack = [...this.redoStack, { name: entry.name, snapshot: this.snapshot() }];
    this.restore(entry.snapshot);
  }

  redo() {
    const entry = this.redoStack.at(-1);
    if (!entry) return;
    this.redoStack = this.redoStack.slice(0, -1);
    this.undoStack = [...this.undoStack, { name: entry.name, snapshot: this.snapshot() }];
    this.restore(entry.snapshot);
  }

  /// Vide l'historique (après une synchro qui a changé les données, une restauration…).
  clearUndo() {
    this.undoStack = [];
    this.redoStack = [];
  }

  private restore(s: Snapshot) {
    this.transactions = s.transactions;
    this.applySettings(s);
    this.saveTransactions();
    this.saveSettings();
  }

  // MARK: - Opérations

  upsert(transaction: Transaction) {
    this.registerUndo("Modifier l’opération");
    const index = this.transactions.findIndex(t => t.id === transaction.id);
    this.transactions = index >= 0 ? this.transactions.with(index, transaction) : [...this.transactions, transaction];
    this.saveTransactions();
  }

  delete(transaction: Transaction) {
    this.registerUndo("Supprimer l’opération");
    this.transactions = this.transactions.filter(t => t.id !== transaction.id);
    this.saveTransactions();
  }

  /// Opérations du mois de `month`, de la plus récente à la plus ancienne.
  transactionsInMonthOf(month: Date): Transaction[] {
    return this.transactions.filter(t => isInMonth(t.date, month)).sort((a, b) => b.date.getTime() - a.date.getTime());
  }

  // MARK: - Catégories

  /// Catégorie d'un identifiant ; une catégorie supprimée renvoie « Sans catégorie ».
  category(id: string): Category {
    return this.categoryIndex.get(id) ?? unknownCategory(id);
  }

  categoryOf(t: Transaction): Category { return this.category(t.categoryID); }

  /// Catégories proposées pour un type d'opération, dans l'ordre choisi.
  categoriesFor(kind: Kind, includeHidden = false): Category[] {
    return this.categories.filter(c => c.kind === kind && (includeHidden || !c.isHidden));
  }

  isUsed(c: Category): boolean {
    return this.usageCount(c) > 0 || this.quickExpenses.some(q => q.categoryID === c.id)
      || this.recurringOperations.some(r => r.categoryID === c.id);
  }

  usageCount(c: Category): number {
    let n = 0;
    for (const t of this.transactions) if (t.categoryID === c.id) n++;
    return n;
  }

  fallbackCategory(kind: Kind): Category { return this.category(fallbackCategoryID(kind)); }

  /// Les catégories « Autre » ne peuvent pas être supprimées.
  isProtected(c: Category): boolean { return c.id === fallbackCategoryID(c.kind); }

  upsertCategory(category: Category) {
    this.registerUndo("Modifier la catégorie");
    const index = this.categories.findIndex(c => c.id === category.id);
    this.categories = index >= 0 ? this.categories.with(index, category) : [...this.categories, category];
    this.saveSettings();
  }

  /// Supprime une catégorie ; ses opérations, ajouts rapides et récurrentes passent dans « Autre ».
  deleteCategory(category: Category) {
    this.registerUndo("Supprimer la catégorie");
    if (this.isProtected(category)) return;
    const fallback = fallbackCategoryID(category.kind);
    if (this.transactions.some(t => t.categoryID === category.id)) {
      this.transactions = this.transactions.map(t => (t.categoryID === category.id ? { ...t, categoryID: fallback } : t));
      this.saveTransactions();
    }
    this.quickExpenses = this.quickExpenses.map(q => (q.categoryID === category.id ? { ...q, categoryID: fallback } : q));
    this.recurringOperations = this.recurringOperations.map(r => (r.categoryID === category.id ? { ...r, categoryID: fallback } : r));
    this.categories = this.categories.filter(c => c.id !== category.id);
    this.saveSettings();
  }

  /// Réordonne les catégories d'un type (`ids` = nouvel ordre complet des catégories de ce type).
  reorderCategories(kind: Kind, ids: string[]) {
    this.registerUndo("Réordonner les catégories");
    const byID = new Map(this.categories.map(c => [c.id, c]));
    const subset = ids.map(id => byID.get(id)).filter((c): c is Category => !!c && c.kind === kind);
    this.categories = [...this.categories.filter(c => c.kind !== kind), ...subset];
    this.saveSettings();
  }

  // MARK: - Ajouts rapides

  upsertQuickExpense(quick: QuickExpense) {
    this.registerUndo("Modifier l’ajout rapide");
    const index = this.quickExpenses.findIndex(q => q.id === quick.id);
    this.quickExpenses = index >= 0 ? this.quickExpenses.with(index, quick) : [...this.quickExpenses, quick];
    this.saveSettings();
  }

  deleteQuickExpense(quick: QuickExpense) {
    this.registerUndo("Supprimer l’ajout rapide");
    this.quickExpenses = this.quickExpenses.filter(q => q.id !== quick.id);
    this.saveSettings();
  }

  reorderQuickExpenses(ids: string[]) {
    this.registerUndo("Réordonner les ajouts rapides");
    const byID = new Map(this.quickExpenses.map(q => [q.id, q]));
    this.quickExpenses = ids.map(id => byID.get(id)).filter((q): q is QuickExpense => !!q);
    this.saveSettings();
  }

  // MARK: - Comptes (base ; le reste est dans logic/accounts.ts)

  account(id: string | null): Account {
    return this.accounts.find(a => a.id === (id ?? MAIN_ACCOUNT_ID)) ?? this.accounts.find(a => a.id === MAIN_ACCOUNT_ID) ?? mainAccount();
  }

  /// Comptes non archivés, dans l'ordre choisi.
  get activeAccounts(): Account[] { return this.accounts.filter(a => !a.isArchived); }

  /// Comptes proposés dans les sélecteurs : actifs, sauf Izly (géré depuis sa page).
  get selectableAccounts(): Account[] { return this.activeAccounts.filter(a => a.kind !== "izly"); }

  /// Compte par défaut ; retombe sur le compte principal s'il a été archivé, supprimé ou s'il est de type Izly.
  get defaultAccount(): Account {
    return this.selectableAccounts.find(a => a.id === this.defaultAccountID) ?? this.account(MAIN_ACCOUNT_ID);
  }

  /// Valeur à enregistrer dans `Transaction.accountID` (null pour le compte principal).
  static storedAccountID(id: string): string | null { return id === MAIN_ACCOUNT_ID ? null : id; }

  /// Compte d'une nouvelle opération : celui demandé, sinon le compte par défaut.
  accountIDForNewTransaction(requested: string | null = null): string | null {
    return BudgetStore.storedAccountID(requested ?? this.defaultAccount.id);
  }

  /// Opération issue d'un ajout rapide (sans compte précis → compte par défaut).
  makeTransaction(quick: QuickExpense, date = new Date()): Transaction {
    return { id: crypto.randomUUID().toUpperCase(), amountCents: quick.amountCents, kind: quick.kind, categoryID: quick.categoryID,
             note: quick.note.length > 0 ? quick.note : quick.name, date, accountID: this.accountIDForNewTransaction(quick.accountID),
             recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null };
  }

  /// Enregistre un ajout rapide comme opération et la renvoie.
  addQuick(quick: QuickExpense, date = new Date()): Transaction {
    const t = this.makeTransaction(quick, date);
    this.upsert(t);
    return t;
  }

  // MARK: - Synchronisation (pont avec src/lib/sync/)

  /// Remplace les données par le résultat d'une fusion, sans créer de « modifications » artificielles.
  /// Renvoie vrai si quelque chose a changé ; l'historique d'annulation est alors vidé.
  applyMergedData(data: Settings & { transactions: Transaction[] }, stamps: Pick<SyncTracker["meta"], "modifiedAt" | "deletedAt" | "settingsAt">): boolean {
    this.sync.isSuspended = true;
    try {
      const txChanged = compactJSON(encodeTransactions(this.transactions, "reference")) !== compactJSON(encodeTransactions(data.transactions, "reference"));
      const settingsChanged = compactJSON(encodeSettings(this.currentSettings(), "reference")) !== compactJSON(encodeSettings(data, "reference"));
      if (txChanged) this.transactions = data.transactions;
      if (settingsChanged) { this.applySettings(data); this.ensureRequiredRecords(); }
      if (txChanged) this.saveTransactions();
      if (settingsChanged) this.saveSettings();
      this.sync.meta = { ...this.sync.meta, modifiedAt: stamps.modifiedAt, deletedAt: stamps.deletedAt, settingsAt: stamps.settingsAt };
      this.sync.baseline = SyncTracker.makeBaseline(this);
      void this.persistSyncMeta();
      if (txChanged || settingsChanged) this.clearUndo();
      return txChanged || settingsChanged;
    } finally {
      this.sync.isSuspended = false;
    }
  }
}
