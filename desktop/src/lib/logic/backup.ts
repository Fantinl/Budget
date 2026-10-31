// Sauvegardes : port de BudgetStore+Backup.swift.
// Sauvegarde automatique quotidienne dans <dossier des données>/Backups/Budget-aaaa-MM-jj_HHmm/ (les deux fichiers JSON),
// 30 sauvegardes conservées ; sauvegarde manuelle vers un fichier JSON combiné ; restauration et import validés
// avant de toucher aux données.

import type { BudgetStore } from "../store.svelte";
import { type Obj, decodeSettings, decodeTransactions, encodeSettings, encodeTransactions, prettyJSON } from "../codec";
import { copyFile, fileInfo, join, listDir, makeDir, readText, removeFile, writeText } from "../platform";

/// Une sauvegarde sur disque : un dossier `Budget-2026-10-17_0930` contenant les deux fichiers JSON.
export interface BackupInfo {
  /// Chemin du dossier.
  path: string;
  date: Date;
  size: number;
  transactionCount: number | null;
}

export const maxBackups = 30;
export const autoBackupIntervalMs = 24 * 3600 * 1000;

const FILES = ["transactions.json", "settings.json"];

const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/// « 2026-10-17_0930 » (heure locale, comme `backupDateFormatter`).
export function backupDateString(d: Date): string {
  return `${pad(d.getFullYear(), 4)}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}${pad(d.getMinutes())}`;
}

function parseBackupDate(text: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})$/.exec(text);
  if (!m) return null;
  const [y, mo, d, h, mi] = m.slice(1).map(Number);
  const date = new Date(y, mo - 1, d, h, mi);
  return date.getFullYear() === y && date.getMonth() === mo - 1 && date.getDate() === d ? date : null;
}

const message = (e: unknown) => (e instanceof Error ? e.message : String(e));

export const backupsDirectory = (s: BudgetStore) => join(s.directory, "Backups");

async function hasData(s: BudgetStore): Promise<boolean> {
  return (await fileInfo(s.transactionsPath)) !== null || (await fileInfo(s.settingsPath)) !== null;
}

// MARK: - Création

/// Sauvegarde automatique : si la plus récente a plus de 24 h (ou s'il n'y en a pas) et qu'il y a des données.
export async function backupIfNeeded(s: BudgetStore, now: Date = new Date()): Promise<void> {
  await s.flush();
  if (!(await hasData(s))) return;
  const latest = (await listBackups(s))[0];
  if (latest && now.getTime() - latest.date.getTime() < autoBackupIntervalMs) return;
  await createBackup(s, now);
}

/// Sauvegarde manuelle.
export async function backupNow(s: BudgetStore): Promise<boolean> {
  await s.flush();
  if (!(await hasData(s))) {
    s.errorMessage = "Il n'y a encore aucune donnée à sauvegarder.";
    return false;
  }
  return (await createBackup(s, new Date())) !== null;
}

async function removeBackupFolder(folder: string) {
  for (const name of FILES) await removeFile(join(folder, name)).catch(() => {});
  await removeFile(folder).catch(() => {});
}

/// Copie les deux fichiers dans un nouveau dossier, puis supprime les plus anciennes sauvegardes.
async function createBackup(s: BudgetStore, now: Date): Promise<string | null> {
  const base = "Budget-" + backupDateString(now);
  const existing = new Set(await listDir(backupsDirectory(s)));
  let name = base;
  for (let suffix = 2; existing.has(name); suffix++) name = `${base}-${suffix}`;
  const folder = join(backupsDirectory(s), name);
  try {
    await makeDir(folder);
    for (const source of [s.transactionsPath, s.settingsPath]) {
      if (await fileInfo(source)) await copyFile(source, join(folder, source.split(/[\\/]/).pop()!));
    }
  } catch (e) {
    await removeBackupFolder(folder);
    s.errorMessage = `La sauvegarde a échoué : ${message(e)}`;
    return null;
  }
  for (const old of (await listBackups(s)).slice(maxBackups)) await removeBackupFolder(old.path);
  return folder;
}

// MARK: - Liste

/// Sauvegardes, de la plus récente à la plus ancienne.
export async function listBackups(s: BudgetStore): Promise<BackupInfo[]> {
  const root = backupsDirectory(s);
  const result: BackupInfo[] = [];
  for (const name of await listDir(root)) {
    if (!name.startsWith("Budget-")) continue;
    const folder = join(root, name);
    const info = await fileInfo(folder);
    // `info` est nul hors de Tauri (faux disque sans dossiers) ; sur disque, ce doit être un dossier.
    if (info && !info.isDir) continue;
    const date = parseBackupDate(name.slice("Budget-".length, "Budget-".length + 15))
      ?? (info ? new Date(info.modifiedMs) : new Date(0));
    let size = 0;
    for (const file of await listDir(folder)) size += (await fileInfo(join(folder, file)))?.size ?? 0;
    let transactionCount: number | null = null;
    try {
      const text = await readText(join(folder, "transactions.json"));
      const value = text === null ? null : JSON.parse(text);
      if (Array.isArray(value)) transactionCount = decodeTransactions(value).length;
    } catch { /* illisible */ }
    result.push({ path: folder, date, size, transactionCount });
  }
  return result.sort((a, b) => b.date.getTime() - a.date.getTime());
}

// MARK: - Restauration

/// Sauvegarde l'état actuel (pour pouvoir annuler), puis remplace les données par celles de la sauvegarde.
export async function restoreBackup(s: BudgetStore, backup: BackupInfo): Promise<boolean> {
  await s.flush();
  const sources = FILES.map(f => join(backup.path, f));
  // Vérifie que la sauvegarde est lisible avant de toucher aux données.
  try {
    const transactions = await readText(sources[0]);
    if (transactions !== null) {
      const value = JSON.parse(transactions);
      if (!Array.isArray(value)) throw new Error("format inattendu");
      decodeTransactions(value);
    }
    const settings = await readText(sources[1]);
    if (settings !== null) {
      const value = JSON.parse(settings);
      if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("format inattendu");
      decodeSettings(value as Obj);
    }
  } catch {
    s.errorMessage = "Cette sauvegarde est illisible, la restauration est annulée. Vos données n'ont pas été modifiées.";
    return false;
  }
  if ((await hasData(s)) && (await createBackup(s, new Date())) === null) return false;
  try {
    const destinations = [s.transactionsPath, s.settingsPath];
    for (let i = 0; i < 2; i++) {
      await removeFile(destinations[i]);
      if (await fileInfo(sources[i])) await copyFile(sources[i], destinations[i]);
    }
  } catch (e) {
    s.errorMessage = `La restauration a échoué : ${message(e)}`;
    await s.reloadFromDisk();
    return false;
  }
  await s.reloadFromDisk();
  s.clearUndo();
  return true;
}

// MARK: - Export / import d'un fichier

/// Contenu du fichier de sauvegarde combiné (transactions + réglages).
export function backupFileData(s: BudgetStore): string {
  return prettyJSON({ transactions: encodeTransactions(s.transactions), settings: encodeSettings(s.currentSettings()) });
}

export const backupFileName = (now: Date = new Date()) => `Budget-sauvegarde-${backupDateString(now)}.json`;

export async function exportBackup(s: BudgetStore, path: string): Promise<boolean> {
  try {
    await writeText(path, backupFileData(s));
    return true;
  } catch (e) {
    s.errorMessage = `L'export de la sauvegarde a échoué : ${message(e)}`;
    return false;
  }
}

/// Remplace toutes les données par celles du fichier (après l'avoir validé et sauvegardé l'état actuel).
export async function importBackup(s: BudgetStore, path: string): Promise<boolean> {
  await s.flush();
  let transactions: ReturnType<typeof decodeTransactions>;
  let settings: Obj;
  try {
    const text = await readText(path);
    if (text === null) throw new Error("fichier introuvable");
    const value = JSON.parse(text) as Obj;
    if (!value || !Array.isArray(value.transactions) || !value.settings || typeof value.settings !== "object") throw new Error("format inattendu");
    transactions = decodeTransactions(value.transactions);
    settings = value.settings as Obj;
    decodeSettings(settings);
  } catch {
    s.errorMessage = "Ce fichier n'est pas une sauvegarde Budget valide. Vos données n'ont pas été modifiées.";
    return false;
  }
  if ((await hasData(s)) && (await createBackup(s, new Date())) === null) return false;
  try {
    await writeText(s.transactionsPath, prettyJSON(encodeTransactions(transactions)));
    await writeText(s.settingsPath, prettyJSON(encodeSettings(decodeSettings(settings))));
  } catch (e) {
    s.errorMessage = `L'import a échoué : ${message(e)}`;
    await s.reloadFromDisk();
    return false;
  }
  await s.reloadFromDisk();
  s.clearUndo();
  return true;
}
