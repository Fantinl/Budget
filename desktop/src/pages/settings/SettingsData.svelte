<script lang="ts">
  // Réglages → Données : dossier des données, sauvegardes, export CSV et import de relevé. Port de SettingsDataView.swift.
  import { onMount } from "svelte";
  import { store } from "../../lib/app.svelte";
  import { appPaths, chooseFile, chooseSaveFile, confirmDialog, makeDir, openExternal, writeText } from "../../lib/platform";
  import { mediumDate, timeOfDay } from "../../lib/format";
  import { startOfMonth } from "../../lib/dates";
  import {
    type BackupInfo, backupFileName, backupNow, backupsDirectory, exportBackup, importBackup, listBackups,
    restoreBackup,
  } from "../../lib/logic/backup";
  import { type CSVPeriod, csvFileName, csvPeriodLabel, csvPeriods, csvText, transactionsForPeriod } from "../../lib/logic/csvExport";
  import Icon from "../../ui/Icon.svelte";
  import DateField from "../../ui/DateField.svelte";
  import ImportStatementSheet from "../import/ImportStatementSheet.svelte";
  import Group from "./Group.svelte";

  let backups = $state<BackupInfo[]>([]);
  let showStatementImport = $state(false);
  let period = $state<CSVPeriod>("thisMonth");
  let customFrom = $state(startOfMonth(new Date()));
  let customTo = $state(new Date());
  let busy = $state(false);

  const paths = appPaths();
  const fileViewer = paths.os === "macos" ? "Finder" : paths.os === "windows" ? "l’Explorateur" : "le gestionnaire de fichiers";

  async function refresh() { backups = await listBackups(store); }
  onMount(() => { void refresh(); });

  const rtf = new Intl.RelativeTimeFormat("fr", { numeric: "auto" });
  /// « Hier », « Il y a 3 heures »… (formatage relatif en toutes lettres).
  function relative(date: Date): string {
    const seconds = Math.round((date.getTime() - Date.now()) / 1000);
    const abs = Math.abs(seconds);
    let text: string;
    if (abs < 60) text = rtf.format(Math.round(seconds / 60) || 0, "minute");
    else if (abs < 3600) text = rtf.format(Math.round(seconds / 60), "minute");
    else if (abs < 86400) text = rtf.format(Math.round(seconds / 3600), "hour");
    else if (abs < 86400 * 30) text = rtf.format(Math.round(seconds / 86400), "day");
    else if (abs < 86400 * 365) text = rtf.format(Math.round(seconds / (86400 * 30)), "month");
    else text = rtf.format(Math.round(seconds / (86400 * 365)), "year");
    return text.charAt(0).toUpperCase() + text.slice(1);
  }

  const number = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 });
  /// Taille de fichier (« 12 Ko », « 1,2 Mo »).
  function bytes(n: number): string {
    if (n < 1000) return `${n} octet${n > 1 ? "s" : ""}`;
    if (n < 1e6) return `${number.format(n / 1000)} Ko`;
    if (n < 1e9) return `${number.format(n / 1e6)} Mo`;
    return `${number.format(n / 1e9)} Go`;
  }

  function detail(backup: BackupInfo): string {
    const parts: string[] = [];
    if (backup.transactionCount !== null) parts.push(backup.transactionCount <= 1 ? `${backup.transactionCount} opération` : `${backup.transactionCount} opérations`);
    parts.push(bytes(backup.size));
    return parts.join(" · ");
  }

  async function saveNow() {
    await backupNow(store);
    await refresh();
  }

  async function restore(backup: BackupInfo) {
    const ok = await confirmDialog(
      "L’état actuel sera sauvegardé avant restauration. Vos opérations et réglages seront remplacés par ceux de la sauvegarde.",
      { title: "Restaurer cette sauvegarde ?", okLabel: "Restaurer" });
    if (!ok) return;
    busy = true;
    await restoreBackup(store, backup);
    busy = false;
    await refresh();
  }

  async function revealBackups() {
    await makeDir(backupsDirectory(store));
    await openExternal(backupsDirectory(store));
  }

  async function exportFile() {
    const path = await chooseSaveFile(backupFileName(), [{ name: "Sauvegarde Budget", extensions: ["json"] }]);
    if (path) await exportBackup(store, path);
  }

  async function importFile() {
    const path = await chooseFile([{ name: "Sauvegarde Budget", extensions: ["json"] }], "Importer une sauvegarde");
    if (!path) return;
    const ok = await confirmDialog(
      "Les données du fichier remplaceront celles de l’app. L’état actuel sera sauvegardé avant l’import.",
      { title: "Remplacer vos données ?", okLabel: "Importer et remplacer" });
    if (!ok) return;
    busy = true;
    await importBackup(store, path);
    busy = false;
    await refresh();
  }

  async function exportCSV() {
    const selected = transactionsForPeriod(store, period, customFrom, customTo);
    const path = await chooseSaveFile(csvFileName(period, customFrom, customTo), [{ name: "CSV", extensions: ["csv"] }]);
    if (!path) return;
    try { await writeText(path, csvText(store, selected)); }
    catch (e) { store.errorMessage = `L’enregistrement a échoué : ${e instanceof Error ? e.message : String(e)}`; }
  }
</script>

<div class="col">
  <Group header="Dossier des données" footer="Les opérations et les réglages sont des fichiers JSON dans ce dossier.">
    <div class="folder">
      <span class="caption path truncate" title={paths.dataDir}>{paths.dataDir}</span>
      <button type="button" class="btn small" onclick={() => openExternal(paths.dataDir)}>
        <Icon name="folder" size={13} /> Révéler
      </button>
    </div>
  </Group>

  <Group header="Sauvegardes" footer="Une sauvegarde automatique est faite chaque jour. Les 30 plus récentes sont conservées.">
    {#if backups.length > 0}
      <div class="line"><span>Dernière sauvegarde</span>
        <span class="secondary">{mediumDate(backups[0].date)} à {timeOfDay(backups[0].date)}</span></div>
    {/if}
    <button type="button" class="action" onclick={saveNow}><Icon name="externaldrive.badge.plus" size={16} color="var(--accent)" /> Sauvegarder maintenant</button>
    {#each backups as backup (backup.path)}
      <div class="backup">
        <div class="texts">
          <span>{relative(backup.date)}</span>
          <span class="caption">{detail(backup)}</span>
        </div>
        <button type="button" class="link" disabled={busy} onclick={() => restore(backup)}>Restaurer…</button>
      </div>
    {/each}
    <button type="button" class="action" onclick={revealBackups}><Icon name="folder" size={16} color="var(--accent)" /> Afficher dans {fileViewer}</button>
    <button type="button" class="action" onclick={exportFile}><Icon name="square.and.arrow.up" size={16} color="var(--accent)" /> Exporter une sauvegarde…</button>
    <button type="button" class="action" disabled={busy} onclick={importFile}><Icon name="square.and.arrow.down" size={16} color="var(--accent)" /> Importer une sauvegarde…</button>
  </Group>

  <Group header="Export" footer="Fichier compatible Excel : séparateur « ; », montants négatifs pour les dépenses.">
    <label class="line"><span>Période</span>
      <select class="field" bind:value={period}>
        {#each csvPeriods as p (p)}<option value={p}>{csvPeriodLabel[p]}</option>{/each}
      </select></label>
    {#if period === "custom"}
      <div class="line"><span>Du</span><DateField label="Du" value={customFrom} onchange={(d) => (customFrom = d)} /></div>
      <div class="line"><span>Au</span><DateField label="Au" value={customTo} onchange={(d) => (customTo = d)} /></div>
    {/if}
    <button type="button" class="action" onclick={exportCSV}><Icon name="tablecells" size={16} color="var(--accent)" /> Exporter en CSV…</button>
  </Group>

  <Group header="Import">
    <button type="button" class="action" onclick={() => (showStatementImport = true)}>
      <Icon name="doc.text.magnifyingglass" size={16} color="var(--accent)" /> Importer un relevé bancaire…
    </button>
  </Group>
</div>

{#if showStatementImport}
  <ImportStatementSheet path={null} onclose={() => (showStatementImport = false)} />
{/if}

<style>
  .folder { width: 100%; justify-content: space-between; }
  .path { flex: 1; user-select: text; -webkit-user-select: text; }
  .line { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: var(--spacing); }
  .action {
    width: 100%; border: none; background: transparent; color: inherit; text-align: left; display: flex; align-items: center; gap: 8px;
  }
  .action:disabled { opacity: 0.5; }
  .backup { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: var(--spacing); }
  .texts { display: flex; flex-direction: column; gap: 2px; }
  .link { border: none; background: transparent; color: var(--accent); }
  .link:disabled { opacity: 0.5; }
</style>
