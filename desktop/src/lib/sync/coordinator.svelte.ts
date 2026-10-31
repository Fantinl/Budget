// Orchestre la synchronisation : lire le distant, fusionner, appliquer au magasin, réécrire.
// Port de SyncCoordinator.swift. Différences avec l'app Mac :
// - le dossier est mémorisé par son chemin (préférence « syncFolder »), sans signet « security-scoped » ;
// - pas de présentateurs de fichiers : la date de modification du fichier est sondée toutes les quelques secondes ;
// - les événements « focus » / « blur » de la fenêtre remplacent `scenePhase`.

import { appPaths, basename, makeDir } from "../platform";
import { pref, type Pref } from "../prefs.svelte";
import type { BudgetStore } from "../store.svelte";
import { removeDuplicateAutoMeals } from "../logic/meals";
import { mergeSnapshots } from "./merge";
import { applySyncSnapshot, emptySnapshot, isSyncPristine, makeSyncSnapshot, sameContent, type SyncSnapshot } from "./snapshot";
import { FolderSyncTransport, SyncError, type SyncTransport } from "./transport";

/// Vrai si le chemin est dans le dossier de données privé de l'app (que l'autre appareil ne voit jamais).
/// Comparaison sans tenir compte de la casse ni du type de séparateur (Windows).
export function isAppPrivateFolder(path: string, dataDir: string): boolean {
  const norm = (p: string) => p.replace(/[\\/]+/g, "/").replace(/\/+$/, "").toLowerCase();
  const folder = norm(path), own = norm(dataDir);
  return folder === own || folder.startsWith(own + "/");
}

export interface CoordinatorOptions {
  /// Autre transport (tests, futur serveur) ; sinon le dossier mémorisé est utilisé.
  transport?: SyncTransport;
  /// Anti-rebond après une modification locale (s) et période de la synchro périodique (s).
  debounceSeconds?: number;
  periodicSeconds?: number;
  /// Période du sondage de la date de modification du fichier (s).
  pollSeconds?: number;
  /// Dossier de données privé de l'app (par défaut `appPaths().dataDir`).
  dataDir?: string;
}

export class SyncCoordinator {
  lastSync = $state<Date | null>(null);
  isSyncing = $state(false);
  lastError = $state<string | null>(null);
  /// Dossier de synchronisation (chemin complet), null = non configurée.
  folder = $state<string | null>(null);

  get isConfigured() { return this.transport !== null; }
  get folderName() { return this.folder ? basename(this.folder) : null; }

  debounceSeconds: number;
  periodicSeconds: number;
  pollSeconds: number;

  private transport: SyncTransport | null = null;
  private readonly folderPref: Pref<string | null> = pref<string | null>("syncFolder", null);
  private readonly lastSyncPref: Pref<string | null> = pref<string | null>("syncLastDate", null);
  private readonly dataDir?: string;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private periodicTimer: ReturnType<typeof setInterval> | null = null;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private resyncRequested = false;
  private seenRemoteMs: number | null = null;
  private detachWindow: (() => void) | null = null;

  constructor(private readonly store: BudgetStore, options: CoordinatorOptions = {}) {
    this.debounceSeconds = options.debounceSeconds ?? 3;
    this.periodicSeconds = options.periodicSeconds ?? 120;
    this.pollSeconds = options.pollSeconds ?? 10;
    this.dataDir = options.dataDir;
    const last = this.lastSyncPref.value;
    this.lastSync = last ? new Date(last) : null;
    if (options.transport) {
      this.transport = options.transport;
    } else if (this.folderPref.value) {
      this.folder = this.folderPref.value;
      this.transport = new FolderSyncTransport(this.folder);
    }
    store.sync.onLocalChange = () => this.scheduleSync();
  }

  // MARK: - Configuration

  /// Mémorise le dossier choisi et lance une première synchro.
  async chooseFolder(path: string): Promise<void> {
    // Le dossier doit être partagé entre les appareils : pas le dossier de données de cette app.
    if (isAppPrivateFolder(path, this.dataDir ?? appPaths().dataDir)) {
      this.lastError = "Ce dossier est privé à cet appareil. Choisis le dossier « Budget » dans iCloud Drive.";
      return;
    }
    this.folderPref.value = path;
    this.folder = path;
    this.transport = new FolderSyncTransport(path);
    this.seenRemoteMs = null;
    this.lastError = null;
    void this.store.persistSyncMeta();
    await this.syncNow();
    this.startPeriodic();
  }

  /// Dossier « Budget » d'iCloud Drive (créé si besoin), s'il existe sur cet ordinateur.
  get defaultFolder(): string | null {
    const icloud = appPaths().icloudDir;
    return icloud ? `${icloud}${/[\\]/.test(icloud) ? "\\" : "/"}Budget` : null;
  }

  async useDefaultFolder(): Promise<void> {
    const path = this.defaultFolder;
    if (!path) { this.lastError = "iCloud Drive est introuvable sur cet ordinateur. Choisis le dossier à la main."; return; }
    try { await makeDir(path); } catch (e) {
      this.lastError = `Le dossier n'a pas pu être créé : ${e instanceof Error ? e.message : String(e)}`;
      return;
    }
    await this.chooseFolder(path);
  }

  /// Arrête la synchronisation (les données restent sur l'appareil ; le fichier du dossier n'est pas touché).
  stop() {
    this.cancelDebounce();
    this.stopTimers();
    this.folderPref.value = null;
    this.lastSyncPref.value = null;
    this.transport = null;
    this.folder = null;
    this.lastSync = null;
    this.lastError = null;
    this.seenRemoteMs = null;
  }

  // MARK: - Déclencheurs

  /// Au lancement de l'app.
  start() { this.appDidBecomeActive(); }

  appDidBecomeActive() {
    if (!this.isConfigured) return;
    void this.syncNow();
    this.startPeriodic();
  }

  appDidResignActive() {
    this.stopTimers();
    this.cancelDebounce();
    // Dernière chance de partir avec les modifications en attente.
    if (this.isConfigured) void this.syncNow();
  }

  /// Branche les événements de la fenêtre (focus = app active, blur = app en arrière-plan).
  attachWindow() {
    if (typeof window === "undefined" || this.detachWindow) return;
    const focus = () => this.appDidBecomeActive();
    const blur = () => this.appDidResignActive();
    window.addEventListener("focus", focus);
    window.addEventListener("blur", blur);
    this.detachWindow = () => { window.removeEventListener("focus", focus); window.removeEventListener("blur", blur); };
  }

  dispose() {
    this.cancelDebounce();
    this.stopTimers();
    this.detachWindow?.();
    this.detachWindow = null;
    this.store.sync.onLocalChange = null;
  }

  /// Anti-rebond : synchronise après `debounceSeconds` sans nouvelle modification.
  scheduleSync() {
    if (!this.isConfigured) return;
    this.cancelDebounce();
    this.debounceTimer = setTimeout(() => { this.debounceTimer = null; void this.syncNow(); }, this.debounceSeconds * 1000);
  }

  private cancelDebounce() {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = null;
  }

  private startPeriodic() {
    this.stopTimers();
    this.periodicTimer = setInterval(() => void this.syncNow(), this.periodicSeconds * 1000);
    this.pollTimer = setInterval(() => void this.pollRemote(), this.pollSeconds * 1000);
  }

  private stopTimers() {
    if (this.periodicTimer) clearInterval(this.periodicTimer);
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.periodicTimer = null;
    this.pollTimer = null;
  }

  /// Une autre instance a-t-elle écrit le fichier ? (remplace les présentateurs de fichiers de l'app Mac)
  private async pollRemote() {
    const transport = this.transport;
    if (!transport?.modifiedMs || this.isSyncing) return;
    try {
      const ms = await transport.modifiedMs();
      if (ms !== null && ms !== this.seenRemoteMs) await this.syncNow();
    } catch { /* l'erreur éventuelle sera remontée par la prochaine synchro */ }
  }

  // MARK: - Synchronisation

  async syncNow(): Promise<void> {
    const transport = this.transport;
    if (!transport) return;
    if (this.isSyncing) { this.resyncRequested = true; return; }
    this.isSyncing = true;
    try {
      do {
        this.resyncRequested = false;
        try {
          await this.runOnce(transport);
          this.lastError = null;
          this.lastSync = new Date();
          this.lastSyncPref.value = this.lastSync.toISOString();
        } catch (e) {
          this.lastError = e instanceof SyncError ? e.message : `La synchronisation a échoué : ${e instanceof Error ? e.message : String(e)}`;
          return;
        }
      } while (this.resyncRequested);
    } finally {
      this.isSyncing = false;
    }
  }

  private async runOnce(transport: SyncTransport): Promise<void> {
    // Les écritures locales en attente doivent être sur le disque avant d'appliquer la fusion.
    await this.store.flush();
    const remote = await transport.read();
    // L'instantané local est pris après la lecture : on garde ce que l'utilisateur a fait pendant l'attente.
    const local = makeSyncSnapshot(this.store);
    let merged: SyncSnapshot;
    if (remote && isSyncPristine(this.store)) {
      merged = remote;   // appareil neuf : on adopte le distant (évite de dupliquer les valeurs par défaut)
    } else {
      merged = mergeSnapshots(local, remote ?? emptySnapshot());
    }
    applySyncSnapshot(this.store, merged);
    // Repas créés pour le même jour sur deux appareils : on en garde un, la suppression part avec l'envoi.
    if (removeDuplicateAutoMeals(this.store)) merged = makeSyncSnapshot(this.store);
    if (!remote || !sameContent(merged, remote)) await transport.write(merged);
    this.seenRemoteMs = (await transport.modifiedMs?.()) ?? null;
  }
}

// MARK: - Instance de l'app

const holder = $state<{ coordinator: SyncCoordinator | null }>({ coordinator: null });

/// Coordinateur de l'app (null avant `startSync`). Réactif.
export function syncCoordinator(): SyncCoordinator | null { return holder.coordinator; }

/// Démarre la synchronisation (si elle est configurée) ; appelé une fois au lancement.
export function startSync(s: BudgetStore): void {
  holder.coordinator?.dispose();
  const coordinator = new SyncCoordinator(s);
  holder.coordinator = coordinator;
  coordinator.attachWindow();
  coordinator.start();
}
