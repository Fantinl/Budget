// Accès au système (fichiers, dossiers, boîtes de dialogue) via les commandes Rust de src-tauri/src/lib.rs.
// Hors de Tauri (aperçu dans un navigateur avec `npm run dev`), un faux disque en localStorage prend le relais.

import { invoke, isTauri } from "@tauri-apps/api/core";

export interface AppPaths {
  dataDir: string;
  icloudDir: string | null;
  homeDir: string;
  os: "macos" | "windows" | "linux";
  /// Mode mesure (variable BUDGET_BENCH_DIR) : dossier de données fictives, null sinon.
  benchDir: string | null;
}

export interface FileInfo {
  modifiedMs: number;
  size: number;
  isDir: boolean;
}

export const inTauri = isTauri();

/// Séparateur de chemin de la plateforme (rempli par `loadPaths`).
let separator = "/";

export function join(...parts: string[]): string {
  return parts.filter(Boolean).join(separator).replace(/[\\/]+/g, separator);
}

export const basename = (path: string) => path.split(/[\\/]/).pop() ?? path;
export const dirname = (path: string) => path.replace(/[\\/][^\\/]*$/, "");

let paths: AppPaths | null = null;

export async function loadPaths(): Promise<AppPaths> {
  if (!paths) {
    paths = inTauri
      ? await invoke<AppPaths>("app_paths")
      : { dataDir: "/navigateur/Budget", icloudDir: "/navigateur/iCloud", homeDir: "/navigateur", os: "macos", benchDir: null };
    separator = paths.os === "windows" ? "\\" : "/";
  }
  return paths;
}

/// Chemins déjà chargés (à appeler après `loadPaths`, fait au démarrage dans main.ts).
export function appPaths(): AppPaths {
  if (!paths) throw new Error("loadPaths() n'a pas été appelé");
  return paths;
}

// MARK: - Fichiers

const fakeKey = (path: string) => `fakefs:${path}`;

/// Faux disque hors de Tauri : localStorage dans un navigateur, mémoire dans les tests (Node).
const memory = new Map<string, string>();
const localStorage: Pick<Storage, "getItem" | "setItem" | "removeItem" | "key" | "length"> =
  typeof globalThis.localStorage?.getItem === "function" ? globalThis.localStorage : {
    getItem: (k: string) => memory.get(k) ?? null,
    setItem: (k: string, v: string) => { memory.set(k, v); },
    removeItem: (k: string) => { memory.delete(k); },
    key: (i: number) => [...memory.keys()][i] ?? null,
    get length() { return memory.size; },
  };

export async function readText(path: string): Promise<string | null> {
  if (!inTauri) return localStorage.getItem(fakeKey(path));
  return invoke<string | null>("read_text", { path });
}

export async function readBytes(path: string): Promise<ArrayBuffer> {
  if (!inTauri) throw new Error("Lecture de fichiers binaires indisponible dans le navigateur.");
  return invoke<ArrayBuffer>("read_bytes", { path });
}

/// Écriture atomique (fichier temporaire puis renommage) ; crée les dossiers manquants.
export async function writeText(path: string, contents: string): Promise<void> {
  if (!inTauri) { localStorage.setItem(fakeKey(path), contents); fakeMtimes.set(path, Date.now()); return; }
  return invoke("write_text", { path, contents });
}

const fakeMtimes = new Map<string, number>();

export async function fileInfo(path: string): Promise<FileInfo | null> {
  if (!inTauri) {
    const v = localStorage.getItem(fakeKey(path));
    return v === null ? null : { modifiedMs: fakeMtimes.get(path) ?? Date.now(), size: v.length, isDir: false };
  }
  return invoke<FileInfo | null>("file_info", { path });
}

export async function listDir(path: string): Promise<string[]> {
  if (!inTauri) {
    const prefix = fakeKey(path.endsWith("/") ? path : path + "/");
    const names = new Set<string>();
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k?.startsWith(prefix)) names.add(k.slice(prefix.length).split("/")[0]);
    }
    return [...names];
  }
  return invoke<string[]>("list_dir", { path });
}

export async function makeDir(path: string): Promise<void> {
  if (inTauri) await invoke("make_dir", { path });
}

export async function removeFile(path: string): Promise<void> {
  if (!inTauri) { localStorage.removeItem(fakeKey(path)); return; }
  return invoke("remove_file", { path });
}

export async function renamePath(from: string, to: string): Promise<void> {
  if (!inTauri) {
    const v = localStorage.getItem(fakeKey(from));
    if (v !== null) { localStorage.setItem(fakeKey(to), v); localStorage.removeItem(fakeKey(from)); }
    return;
  }
  return invoke("rename_path", { from, to });
}

export async function copyFile(from: string, to: string): Promise<void> {
  if (!inTauri) {
    const v = localStorage.getItem(fakeKey(from));
    if (v !== null) localStorage.setItem(fakeKey(to), v);
    return;
  }
  return invoke("copy_file", { from, to });
}

// MARK: - Boîtes de dialogue natives

export interface FileFilter { name: string; extensions: string[] }

/// Choisir un fichier à ouvrir ; null si annulé.
export async function chooseFile(filters?: FileFilter[], title?: string): Promise<string | null> {
  if (!inTauri) return null;
  const { open } = await import("@tauri-apps/plugin-dialog");
  const result = await open({ multiple: false, directory: false, filters, title });
  return typeof result === "string" ? result : null;
}

export async function chooseFolder(title?: string): Promise<string | null> {
  if (!inTauri) return null;
  const { open } = await import("@tauri-apps/plugin-dialog");
  const result = await open({ multiple: false, directory: true, title });
  return typeof result === "string" ? result : null;
}

/// Choisir où enregistrer un fichier ; null si annulé.
export async function chooseSaveFile(defaultName: string, filters?: FileFilter[]): Promise<string | null> {
  if (!inTauri) return null;
  const { save } = await import("@tauri-apps/plugin-dialog");
  return (await save({ defaultPath: defaultName, filters })) ?? null;
}

/// Confirmation native (« Supprimer ? »). `danger` = bouton destructif.
export async function confirmDialog(message: string, options: { title?: string; okLabel?: string; cancelLabel?: string } = {}): Promise<boolean> {
  if (!inTauri) return window.confirm(message);
  const { ask } = await import("@tauri-apps/plugin-dialog");
  return ask(message, { title: options.title ?? "Budget", kind: "warning",
                        okLabel: options.okLabel ?? "OK", cancelLabel: options.cancelLabel ?? "Annuler" });
}

export async function alertDialog(message: string, title = "Budget"): Promise<void> {
  if (!inTauri) { window.alert(message); return; }
  const { message: show } = await import("@tauri-apps/plugin-dialog");
  await show(message, { title });
}

/// Ouvre un lien dans le navigateur, ou montre un fichier / dossier dans l'Explorateur (le Finder sur Mac).
export async function openExternal(target: string): Promise<void> {
  if (!inTauri) { window.open(target, "_blank"); return; }
  const opener = await import("@tauri-apps/plugin-opener");
  if (/^https?:/.test(target)) await opener.openUrl(target); else await opener.revealItemInDir(target);
}
