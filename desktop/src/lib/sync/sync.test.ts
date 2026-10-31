// Port de SyncMergeTests, SyncTrackingTests, SyncFolderTests et SyncFolderChoiceTests.
import { afterEach, describe, expect, it } from "vitest";
import { type Category, type Transaction, newAccount, newID } from "../model";
import { readText, removeFile, writeText } from "../platform";
import type { BudgetStore } from "../store.svelte";
import { day, expense, makeStore, tick } from "../test/support";
import { SyncCoordinator, isAppPrivateFolder } from "./coordinator.svelte";
import { mergeSnapshots } from "./merge";
import { type SyncSnapshot, decodeSnapshot, isSyncPristine, newSnapshot, sameContent, serializeSnapshot } from "./snapshot";
import { FolderSyncTransport } from "./transport";
import { SyncKey } from "./tracker";

const base = new Date(1_800_000_000 * 1000);
const at = (seconds: number) => new Date(base.getTime() + seconds * 1000);

// MARK: - Fusion

function snapshot(device: string, o: { transactions?: [Transaction, number][]; deleted?: [Transaction, number][];
                                       categories?: Category[]; at?: number } = {}): SyncSnapshot {
  const s = newSnapshot(device, at(o.at ?? 0));
  s.categories = o.categories ?? [];
  for (const [t, stamp] of o.transactions ?? []) { s.transactions.push(t); s.modifiedAt[SyncKey.transaction + t.id] = at(stamp); }
  for (const [t, stamp] of o.deleted ?? []) s.deletedAt[SyncKey.transaction + t.id] = at(stamp);
  return s;
}

const tx = (note: string): Transaction => ({ ...expense(10, "otherExpense", day(2026, 10, 1)), note });
const merge = (a: SyncSnapshot, b: SyncSnapshot) => mergeSnapshots(a, b, base);
/// Égalité stricte de deux instantanés (comme `==` en Swift), via leur forme écrite.
const same = (a: SyncSnapshot, b: SyncSnapshot) => expect(serializeSnapshot(a)).toBe(serializeSnapshot(b));
const category = (id: string): Category => ({ id, label: id, icon: "x", kind: "expense", colorIndex: 0, isHidden: false,
                                              monthlyBudgetCents: null, budgetOverridesCents: null, budgetRollover: null });

describe("SyncMerge", () => {
  it("l'ajout des deux côtés donne l'union", () => {
    const m = merge(snapshot("A", { transactions: [[tx("A"), 1]] }), snapshot("B", { transactions: [[tx("B"), 2]] }));
    expect(new Set(m.transactions.map(t => t.note))).toEqual(new Set(["A", "B"]));
  });

  it("une modification concurrente : la plus récente gagne", () => {
    const t = tx("origine");
    const older = { ...t, note: "ancien" }, newer = { ...t, note: "récent" };
    const m1 = merge(snapshot("A", { transactions: [[older, 5]] }), snapshot("B", { transactions: [[newer, 9]] }));
    const m2 = merge(snapshot("B", { transactions: [[newer, 9]] }), snapshot("A", { transactions: [[older, 5]] }));
    expect(m1.transactions[0].note).toBe("récent");
    expect(m2.transactions[0].note).toBe("récent");
    expect(m1.transactions).toHaveLength(1);
  });

  it("une suppression plus récente que la modification gagne", () => {
    const t = tx("à supprimer");
    const m = merge(snapshot("A", { transactions: [[t, 5]] }), snapshot("B", { deleted: [[t, 8]] }));
    expect(m.transactions).toEqual([]);
    expect(m.deletedAt[SyncKey.transaction + t.id]).toBeDefined();
    expect(m.modifiedAt[SyncKey.transaction + t.id]).toBeUndefined();
  });

  it("une modification plus récente que la suppression gagne", () => {
    const t = tx("sauvée");
    const m = merge(snapshot("A", { transactions: [[t, 9]] }), snapshot("B", { deleted: [[t, 8]] }));
    expect(m.transactions).toHaveLength(1);
    expect(Object.keys(m.deletedAt)).toEqual([]);
  });

  it("idempotence et commutativité", () => {
    const shared = tx("commun"), onlyA = tx("a"), onlyB = tx("b"), gone = tx("gone");
    const edited = { ...shared, note: "modifié" };
    const a = snapshot("A", { transactions: [[shared, 1], [onlyA, 2], [gone, 3]], at: 10 });
    const b = snapshot("B", { transactions: [[edited, 4], [onlyB, 2]], deleted: [[gone, 5]], at: 11 });
    const m = merge(a, b);
    same(merge(a, m), m);
    same(merge(m, a), m);
    same(merge(m, m), m);
    expect(sameContent(merge(b, a), m)).toBe(true);
    expect(m.transactions).toHaveLength(3);
  });

  it("une égalité parfaite est symétrique et idempotente", () => {
    const t = tx("x");
    const other = { ...t, note: "y" };
    const a = snapshot("A", { transactions: [[t, 5]] });
    const b = snapshot("B", { transactions: [[other, 5]] });
    const m = merge(a, b);
    expect(sameContent(merge(b, a), m)).toBe(true);
    same(merge(a, m), m);
    same(merge(b, m), merge(m, b));
  });

  it("l'ordre d'une liste suit la version la plus récente, puis ajoute les inconnus", () => {
    const [c1, c2, c3, c4] = ["1", "2", "3", "4"].map(category);
    const a = snapshot("A", { categories: [c1, c2, c3] });
    const b = snapshot("B", { categories: [c3, c2, c1, c4] });
    a.settingsAt[SyncKey.orderCategories] = at(5);
    b.settingsAt[SyncKey.orderCategories] = at(9);
    expect(merge(a, b).categories.map(c => c.id)).toEqual(["3", "2", "1", "4"]);
    // L'ordre de A est plus récent : « 4 », inconnu de A, arrive à la fin.
    a.settingsAt[SyncKey.orderCategories] = at(20);
    expect(merge(a, b).categories.map(c => c.id)).toEqual(["1", "2", "3", "4"]);
    expect(merge(b, a).categories.map(c => c.id)).toEqual(["1", "2", "3", "4"]);
  });

  it("le compte par défaut : le plus récent gagne", () => {
    const a = snapshot("A"), b = snapshot("B");
    a.defaultAccountID = "livret"; a.settingsAt[SyncKey.defaultAccount] = at(9);
    b.defaultAccountID = "main"; b.settingsAt[SyncKey.defaultAccount] = at(3);
    expect(merge(a, b).defaultAccountID).toBe("livret");
    expect(merge(b, a).defaultAccountID).toBe("livret");
  });

  it("le plan du budget : le plus récent gagne", () => {
    const a = snapshot("A"), b = snapshot("B");
    a.budgetPlan = { savingsGoalCents: 30000, expectedIncomeCents: null }; a.settingsAt[SyncKey.budgetPlan] = at(2);
    b.budgetPlan = { savingsGoalCents: 15000, expectedIncomeCents: null }; b.settingsAt[SyncKey.budgetPlan] = at(8);
    expect(merge(a, b).budgetPlan?.savingsGoalCents).toBe(15000);
    expect(merge(b, a).budgetPlan?.savingsGoalCents).toBe(15000);
  });

  it("le plan du budget survit à un ancien fichier distant sans cette clé", () => {
    const a = snapshot("A");
    a.budgetPlan = { savingsGoalCents: 30000, expectedIncomeCents: null }; a.settingsAt[SyncKey.budgetPlan] = at(2);
    const json = JSON.parse(serializeSnapshot(snapshot("B")));
    delete json.budgetPlan;
    const old = decodeSnapshot(json);
    expect(old.budgetPlan).toBeNull();
    expect(merge(a, old).budgetPlan?.savingsGoalCents).toBe(30000);
    expect(merge(old, a).budgetPlan?.savingsGoalCents).toBe(30000);
  });

  it("les vieilles tombes sont purgées", () => {
    const old = tx("vieux"), recent = tx("récent");
    const day90 = 90 * 24 * 3600;
    const a = snapshot("A", { deleted: [[old, -day90 - 100], [recent, -day90 + 3600]] });
    const m = merge(a, snapshot("B"));
    expect(m.deletedAt[SyncKey.transaction + old.id]).toBeUndefined();
    expect(m.deletedAt[SyncKey.transaction + recent.id]).toBeDefined();
  });

  it("l'instantané s'écrit en JSON compact trié, dates en secondes depuis 2001", () => {
    const s = snapshot("A", { transactions: [[tx("n"), 1]], at: 0 });
    const text = serializeSnapshot(s);
    expect(text).not.toContain("\n");
    const keys = Object.keys(JSON.parse(text));
    expect(keys).toEqual([...keys].sort());
    expect(JSON.parse(text).date).toBe(1_800_000_000 - 978_307_200);
    same(decodeSnapshot(JSON.parse(text)), s);
  });
});

// MARK: - Suivi

describe("SyncTracking", () => {
  let now = new Date(1_800_000_000 * 1000);
  const advance = () => { now = new Date(now.getTime() + 10_000); };
  async function tracked(dir?: string) {
    const s = await makeStore(dir);
    s.sync.clock = () => now;
    return s;
  }

  it("suit l'ajout, la modification et la suppression d'une opération", async () => {
    now = new Date(1_800_000_000 * 1000);
    const s = await tracked();
    const t = { ...expense(5, "otherExpense", day(2026, 10, 1)), note: "a" };
    const key = SyncKey.transaction + t.id;
    s.upsert(t);
    expect(s.sync.meta.modifiedAt[key]).toEqual(now);
    advance();
    const edited = { ...t, note: "b" };
    s.upsert(edited);
    expect(s.sync.meta.modifiedAt[key]).toEqual(now);
    advance();
    s.upsert(edited);   // identique : pas de nouvelle date
    expect(s.sync.meta.modifiedAt[key]).toEqual(new Date(now.getTime() - 10_000));
    s.delete(edited);
    expect(s.sync.meta.deletedAt[key]).toEqual(now);
    expect(s.sync.meta.modifiedAt[key]).toBeUndefined();
  });

  it("suit les réglages et les métadonnées survivent au redémarrage", async () => {
    now = new Date(1_800_000_000 * 1000);
    const s = await tracked("/test/redemarrage");
    const tag = { id: newID(), name: "vacances", colorIndex: 1 };
    const quick = { id: newID(), name: "Thé", amountCents: 200, kind: "expense" as const, categoryID: "restaurants", note: "", accountID: null };
    s.tags = [...s.tags, tag];
    s.quickExpenses = [...s.quickExpenses, quick];
    s.saveSettings();
    expect(s.sync.meta.modifiedAt[SyncKey.tag + tag.id]).toEqual(now);
    expect(s.sync.meta.modifiedAt[SyncKey.quick + quick.id]).toEqual(now);
    advance();
    s.quickExpenses = s.quickExpenses.filter(q => q.id !== quick.id);
    s.saveSettings();
    expect(s.sync.meta.deletedAt[SyncKey.quick + quick.id]).toEqual(now);
    await s.flush();
    const reloaded = await makeStore("/test/redemarrage");
    expect(reloaded.sync.meta).toEqual(s.sync.meta);
  });

  it("supprimer une catégorie date aussi les enregistrements réaffectés", async () => {
    now = new Date(1_800_000_000 * 1000);
    const s = await tracked();
    const t = expense(5, "health", day(2026, 10, 1));
    s.upsert(t);
    advance();
    await tick();
    s.deleteCategory(s.category("health"));
    expect(s.sync.meta.deletedAt[SyncKey.category + "health"]).toEqual(now);
    expect(s.sync.meta.modifiedAt[SyncKey.transaction + t.id]).toEqual(now);
  });

  it("réordonner ne date que l'ordre", async () => {
    now = new Date(1_800_000_000 * 1000);
    const s = await tracked();
    const first = s.quickExpenses[0];
    s.quickExpenses = [...s.quickExpenses.slice(1), first];
    s.saveSettings();
    expect(s.sync.meta.settingsAt[SyncKey.orderQuick]).toEqual(now);
    expect(s.sync.meta.modifiedAt[SyncKey.quick + first.id]).toBeUndefined();
    advance();
    s.quickExpenses = [...s.quickExpenses, { id: newID(), name: "Neuf", amountCents: 100, kind: "expense", categoryID: "groceries", note: "", accountID: null }];
    s.saveSettings();
    expect(s.sync.meta.settingsAt[SyncKey.orderQuick]).toEqual(new Date(now.getTime() - 10_000));   // un ajout ne change pas l'ordre relatif
  });

  it("date le compte par défaut", async () => {
    now = new Date(1_800_000_000 * 1000);
    const s = await tracked();
    const livret = newAccount({ name: "Livret", kind: "livretA", colorIndex: 1 });
    s.accounts = [...s.accounts, livret];
    s.saveSettings();
    advance();
    s.defaultAccountID = livret.id;
    s.saveSettings();
    expect(s.sync.meta.settingsAt[SyncKey.defaultAccount]).toEqual(now);
  });

  it("date le plan du budget", async () => {
    now = new Date(1_800_000_000 * 1000);
    const s = await tracked();
    advance();
    s.budgetPlan = { savingsGoalCents: 20000, expectedIncomeCents: null };
    s.saveSettings();
    expect(s.sync.meta.settingsAt[SyncKey.budgetPlan]).toEqual(now);
  });

  it("sans métadonnées au premier lancement, tout est daté par les fichiers", async () => {
    const dir = "/test/premier-lancement";
    const s = await makeStore(dir);
    const t = expense(5, "otherExpense", day(2026, 10, 1));
    s.upsert(t);
    s.tags = [{ id: "x", name: "x", colorIndex: 0 }];
    s.saveSettings();
    await s.flush();
    await removeFile(s.syncMetaPath);
    const fresh = await makeStore(dir);
    const stamp = fresh.sync.meta.modifiedAt[SyncKey.transaction + t.id];
    expect(Math.abs(stamp.getTime() - Date.now())).toBeLessThan(5000);
    expect(Math.abs(fresh.sync.meta.modifiedAt[SyncKey.category + "groceries"].getTime() - stamp.getTime())).toBeLessThan(5000);
    expect(fresh.sync.meta.settingsAt[SyncKey.orderCategories]).toBeDefined();
  });

  it("un magasin tout neuf n'a pas de métadonnées", async () => {
    expect(isSyncPristine(await makeStore())).toBe(true);
  });
  // « testRestoreCountsAsModification » : couvert avec la sauvegarde (logic/backup.ts), pas dans le périmètre de la synchro.
});

// MARK: - Dossier partagé

describe("SyncFolder", () => {
  let now: Date;
  let storeA: BudgetStore, storeB: BudgetStore;
  let syncA: SyncCoordinator, syncB: SyncCoordinator;
  let cloud: string;
  const advance = (s = 10) => { now = new Date(now.getTime() + s * 1000); };
  const coordinators: SyncCoordinator[] = [];

  async function setup() {
    now = new Date(1_800_000_000 * 1000);
    const id = newID();
    cloud = `/test/${id}/icloud`;
    storeA = await makeStore(`/test/${id}/A`);
    storeB = await makeStore(`/test/${id}/B`);
    for (const s of [storeA, storeB]) s.sync.clock = () => now;
    const make = (s: BudgetStore) => {
      const c = new SyncCoordinator(s, { transport: new FolderSyncTransport(cloud), debounceSeconds: 3600, periodicSeconds: 3600 });
      coordinators.push(c);
      return c;
    };
    syncA = make(storeA);
    syncB = make(storeB);
  }
  afterEach(() => { for (const c of coordinators.splice(0)) c.dispose(); });

  it("un ajout sur A apparaît sur B", async () => {
    await setup();
    const t = { ...expense(12, "otherExpense", day(2026, 10, 1)), note: "Pain" };
    storeA.upsert(t);
    await syncA.syncNow();
    expect(syncA.lastError).toBeNull();
    await syncB.syncNow();
    expect(syncB.lastError).toBeNull();
    expect(storeB.transactions).toEqual([t]);
    expect(syncB.lastSync).not.toBeNull();
    expect(await readText(`${cloud}/Budget-sync.json`)).not.toBeNull();
  });

  it("une suppression sur B disparaît sur A, sans ressusciter", async () => {
    await setup();
    const t = expense(12, "otherExpense", day(2026, 10, 1));
    storeA.upsert(t);
    await syncA.syncNow(); await syncB.syncNow();
    advance();
    storeB.delete(t);
    await syncB.syncNow(); await syncA.syncNow();
    expect(storeA.transactions).toEqual([]);
    await syncB.syncNow(); await syncA.syncNow();
    expect(storeA.transactions).toEqual([]);
    expect(storeB.transactions).toEqual([]);
  });

  it("les modifications concurrentes sont résolues", async () => {
    await setup();
    const t = { ...expense(12, "otherExpense", day(2026, 10, 1)), note: "origine" };
    storeA.upsert(t);
    await syncA.syncNow(); await syncB.syncNow();
    advance();
    storeA.upsert({ ...t, note: "depuis A" });
    storeA.tags = [...storeA.tags, { id: "ta", name: "a", colorIndex: 0 }]; storeA.saveSettings();
    advance();
    storeB.upsert({ ...t, note: "depuis B" });
    storeB.tags = [...storeB.tags, { id: "tb", name: "b", colorIndex: 1 }]; storeB.saveSettings();
    await syncA.syncNow();
    await syncB.syncNow();
    await syncA.syncNow();
    expect(storeA.transactions[0].note).toBe("depuis B");
    expect(storeB.transactions[0].note).toBe("depuis B");
    expect(new Set(storeA.tags.map(x => x.id))).toEqual(new Set(["ta", "tb"]));
    expect(new Set(storeB.tags.map(x => x.id))).toEqual(new Set(["ta", "tb"]));
  });

  it("la synchro s'enregistre sur disque sans fausses modifications", async () => {
    await setup();
    storeA.upsert(expense(1, "otherExpense", day(2026, 10, 1)));
    await syncA.syncNow(); await syncB.syncNow();
    const before = { ...storeB.sync.meta.modifiedAt };
    await syncB.syncNow();
    expect(storeB.sync.meta.modifiedAt).toEqual(before);
    await storeB.flush();
    expect((await makeStore(storeB.directory)).transactions).toEqual(storeB.transactions);
  });

  it("l'annulation après une synchro est vidée quand les données changent", async () => {
    await setup();
    storeA.upsert(expense(3, "otherExpense", day(2026, 10, 1)));
    await tick();
    await syncA.syncNow();
    advance();
    storeB.upsert(expense(4, "otherExpense", day(2026, 10, 2)));
    await syncB.syncNow();
    await syncA.syncNow();
    expect(storeA.transactions).toHaveLength(2);
    expect(storeA.canUndo).toBe(false);   // l'historique est vidé quand une synchro change les données
    storeA.undo();
    expect(storeA.transactions).toHaveLength(2);
    // Une annulation sans changement venu de l'autre appareil reste possible.
    advance();
    storeA.upsert(expense(5, "otherExpense", day(2026, 10, 3)));
    await tick();
    await syncA.syncNow();
    expect(storeA.canUndo).toBe(true);
    storeA.undo();
    expect(storeA.transactions).toHaveLength(2);
  });

  it("un fichier distant illisible est signalé et conservé", async () => {
    await setup();
    const file = `${cloud}/Budget-sync.json`;
    await writeText(file, "pas du json");
    storeA.upsert(expense(1, "otherExpense", day(2026, 10, 1)));
    await syncA.syncNow();
    expect(syncA.lastError).not.toBeNull();
    expect(await readText(file)).toBe("pas du json");
  });

  it("un fichier d'une version plus récente est signalé", async () => {
    await setup();
    await writeText(`${cloud}/Budget-sync.json`, JSON.stringify({ version: 2, deviceID: "x", nouveau: true }));
    await syncA.syncNow();
    expect(syncA.lastError).toContain("version plus récente");
  });

  it("les valeurs par défaut ne sont pas dupliquées sur un nouvel appareil", async () => {
    await setup();
    storeA.quickExpenses = [...storeA.quickExpenses, { id: newID(), name: "Thé", amountCents: 200, kind: "expense", categoryID: "restaurants", note: "", accountID: null }];
    storeA.saveSettings();
    await syncA.syncNow(); await syncB.syncNow();
    expect(storeB.quickExpenses.map(q => q.id)).toEqual(storeA.quickExpenses.map(q => q.id));
    expect(storeB.categories).toHaveLength(storeA.categories.length);
  });
});

// MARK: - Choix du dossier

describe("SyncFolderChoice", () => {
  it("refuse le dossier de données de l'app", () => {
    const own = "/Users/moi/Library/Application Support/Budget Proto";
    expect(isAppPrivateFolder(own, own)).toBe(true);
    expect(isAppPrivateFolder(`${own}/Sync`, own)).toBe(true);
    expect(isAppPrivateFolder("C:\\Users\\moi\\AppData\\Roaming\\Budget\\Sync", "c:/users/moi/AppData/Roaming/Budget")).toBe(true);
  });

  it("accepte un dossier partagé", () => {
    const own = "/Users/moi/Library/Application Support/Budget Proto";
    expect(isAppPrivateFolder("/Users/moi/Library/Mobile Documents/com~apple~CloudDocs/Budget", own)).toBe(false);
    expect(isAppPrivateFolder("/tmp", own)).toBe(false);
    expect(isAppPrivateFolder(`${own} 2`, own)).toBe(false);
  });
});
