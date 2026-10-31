// Transport d'un instantané : port de SyncTransport.swift (dossier partagé, iCloud Drive aujourd'hui).
// La fusion (merge.ts) ne dépend pas du transport.

import { fileInfo, inTauri, join, readText, writeText } from "../platform";
import { CURRENT_VERSION, type SyncSnapshot, decodeSnapshot, serializeSnapshot } from "./snapshot";

export interface SyncTransport {
  /// Dernier instantané publié, ou null s'il n'y en a pas encore.
  read(): Promise<SyncSnapshot | null>;
  write(snapshot: SyncSnapshot): Promise<void>;
  /// Date de modification du fichier partagé (sondage des changements), absente si le transport ne sait pas la donner.
  modifiedMs?(): Promise<number | null>;
}

export type SyncErrorKind = "folderUnavailable" | "downloadTimeout" | "unreadable" | "newerFormat" | "failed";

export class SyncError extends Error {
  constructor(readonly kind: SyncErrorKind, detail = "") {
    super(SyncError.describe(kind, detail));
  }

  static describe(kind: SyncErrorKind, detail: string): string {
    switch (kind) {
      case "folderUnavailable": return "Le dossier de synchronisation est introuvable. Choisis-le à nouveau.";
      case "downloadTimeout": return "Le fichier de synchronisation n'a pas fini de se télécharger depuis iCloud. Réessaie dans un instant.";
      case "unreadable": return "Le fichier de synchronisation est illisible. Rien n'a été modifié.";
      case "newerFormat": return "Les données de synchronisation viennent d'une version plus récente de l'app. Mets cette app à jour.";
      case "failed": return `La synchronisation a échoué : ${detail}`;
    }
  }
}

const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));

export const SYNC_FILE_NAME = "Budget-sync.json";

/// Échange via un fichier `Budget-sync.json` dans un dossier choisi par l'utilisateur (iCloud Drive).
export class FolderSyncTransport implements SyncTransport {
  constructor(readonly folder: string, readonly downloadTimeoutMs = 10_000) {}

  get filePath() { return join(this.folder, SYNC_FILE_NAME); }

  async read(): Promise<SyncSnapshot | null> {
    await this.ensureDownloaded();
    const text = await readText(this.filePath);
    if (text === null) return null;
    let json: unknown;
    try { json = JSON.parse(text); } catch { throw new SyncError("unreadable"); }
    let snapshot: SyncSnapshot;
    try {
      snapshot = decodeSnapshot(json as Record<string, unknown>);
    } catch {
      // Version plus récente dont le format ne se lit pas ? On la distingue d'un fichier cassé.
      const version = (json as { version?: unknown } | null)?.version;
      if (typeof version === "number" && version > CURRENT_VERSION) throw new SyncError("newerFormat");
      throw new SyncError("unreadable");
    }
    if (snapshot.version > CURRENT_VERSION) throw new SyncError("newerFormat");
    return snapshot;
  }

  async write(snapshot: SyncSnapshot): Promise<void> {
    if (!(await this.folderExists())) throw new SyncError("folderUnavailable");
    await writeText(this.filePath, serializeSnapshot(snapshot));
  }

  /// Hors de Tauri (aperçu navigateur, tests), le faux disque n'a pas de dossiers : on les suppose présents.
  private async folderExists(): Promise<boolean> {
    return !inTauri || (await fileInfo(this.folder))?.isDir === true;
  }

  /// Date de modification du fichier de synchro (sondage des changements), null s'il n'existe pas.
  async modifiedMs(): Promise<number | null> {
    return (await fileInfo(this.filePath))?.modifiedMs ?? null;
  }

  /// Le dossier doit exister ; un fichier iCloud encore en cours de téléchargement (« .Budget-sync.json.icloud ») est attendu un peu.
  private async ensureDownloaded(): Promise<void> {
    if (!(await this.folderExists())) throw new SyncError("folderUnavailable");
    const placeholder = join(this.folder, `.${SYNC_FILE_NAME}.icloud`);
    const deadline = Date.now() + this.downloadTimeoutMs;
    while (await fileInfo(placeholder)) {
      if (Date.now() > deadline) throw new SyncError("downloadTimeout");
      await sleep(250);
    }
  }
}
