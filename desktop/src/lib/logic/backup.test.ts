// Port de BackupTests.swift.
import { describe, expect, it } from "vitest";
import { day, expense, makeStore, tick } from "../test/support";
import { backupFileData, backupIfNeeded, backupNow, exportBackup, importBackup, listBackups, maxBackups, restoreBackup } from "./backup";
import { readText, writeText } from "../platform";
import { newAccount } from "../model";

describe("Sauvegardes", () => {
  it("sauvegarde puis restaure", async () => {
    const s = await makeStore();
    s.upsert(expense(1, "otherExpense", day(2026, 10, 1)));
    s.upsert(expense(2, "otherExpense", day(2026, 10, 2)));
    expect(await backupNow(s)).toBe(true);
    s.transactions = [];
    s.saveTransactions();
    await s.flush();
    const backups = await listBackups(s);
    expect(backups).toHaveLength(1);
    expect(backups[0].transactionCount).toBe(2);
    expect(await restoreBackup(s, backups[0])).toBe(true);
    expect(s.transactions).toHaveLength(2);
    // L'état courant (vide) a été sauvegardé avant la restauration.
    expect((await listBackups(s)).length).toBeGreaterThanOrEqual(2);
  });

  it("refuse de sauvegarder sans données", async () => {
    const s = await makeStore();
    expect(await backupNow(s)).toBe(false);
    expect(s.errorMessage).not.toBeNull();
  });

  it("sauvegarde automatique au plus une fois par jour", async () => {
    const s = await makeStore();
    s.upsert(expense(1, "otherExpense", day(2026, 10, 1)));
    const t0 = day(2026, 10, 1);
    await backupIfNeeded(s, t0);
    expect(await listBackups(s)).toHaveLength(1);
    await backupIfNeeded(s, new Date(t0.getTime() + 3600_000));
    expect(await listBackups(s)).toHaveLength(1);
  });

  it("supprime les plus anciennes sauvegardes", async () => {
    const s = await makeStore();
    s.upsert(expense(1, "otherExpense", day(2026, 10, 1)));
    for (let i = 0; i < maxBackups + 3; i++) await backupIfNeeded(s, new Date(day(2026, 1, 1).getTime() + i * 2 * 86_400_000));
    expect(await listBackups(s)).toHaveLength(maxBackups);
  });

  it("une sauvegarde illisible ne touche pas aux données", async () => {
    const s = await makeStore();
    s.upsert(expense(1, "otherExpense", day(2026, 10, 1)));
    expect(await backupNow(s)).toBe(true);
    const backup = (await listBackups(s))[0];
    await writeText(`${backup.path}/transactions.json`, "cassé");
    expect(await restoreBackup(s, backup)).toBe(false);
    expect(s.transactions).toHaveLength(1);
    expect(s.errorMessage).not.toBeNull();
  });

  it("exporte et importe un fichier", async () => {
    const s = await makeStore();
    s.upsert(expense(5, "groceries", day(2026, 10, 1)));
    s.accounts = [...s.accounts, newAccount({ name: "Livret", kind: "livretA", colorIndex: 1, initialBalanceCents: 1000 })];
    s.saveSettings();
    await s.flush();
    const file = "/test/export/export.json";
    expect(await exportBackup(s, file)).toBe(true);
    expect(JSON.parse((await readText(file))!).transactions).toHaveLength(1);
    expect(JSON.parse(backupFileData(s)).settings.accounts).toHaveLength(2);

    const other = await makeStore();
    expect(await importBackup(other, file)).toBe(true);
    expect(other.transactions).toEqual(s.transactions);
    expect(other.accounts).toEqual(s.accounts);
    expect((await makeStore(other.directory)).transactions).toHaveLength(1);
  });

  it("un fichier invalide laisse les données intactes", async () => {
    const s = await makeStore();
    s.upsert(expense(5, "otherExpense", day(2026, 10, 1)));
    await tick();
    await writeText("/test/export/bad.json", "{}");
    expect(await importBackup(s, "/test/export/bad.json")).toBe(false);
    expect(s.transactions).toHaveLength(1);
  });
});
