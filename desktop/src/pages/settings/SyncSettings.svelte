<!-- Réglages → Synchronisation : port de SettingsSyncView.swift (dossier partagé entre les appareils, par exemple iCloud Drive). -->
<script lang="ts">
  import { onMount } from "svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import { chooseFolder, confirmDialog } from "../../lib/platform";
  import { syncCoordinator } from "../../lib/sync/coordinator.svelte";

  const sync = $derived(syncCoordinator());
  const hasICloud = $derived(sync ? sync.defaultFolder !== null : false);

  // Rafraîchit « il y a … » toutes les 30 secondes.
  let now = $state(Date.now());
  onMount(() => {
    const timer = setInterval(() => (now = Date.now()), 30_000);
    return () => clearInterval(timer);
  });

  function relative(date: Date, current: number): string {
    const seconds = (current - date.getTime()) / 1000;
    if (seconds < 45) return "à l'instant";
    const formatter = new Intl.RelativeTimeFormat("fr-FR", { numeric: "always", style: "short" });
    if (seconds < 3600) return formatter.format(-Math.round(seconds / 60), "minute");
    if (seconds < 86_400) return formatter.format(-Math.round(seconds / 3600), "hour");
    return formatter.format(-Math.round(seconds / 86_400), "day");
  }

  async function pick() {
    if (!sync) return;
    const path = await chooseFolder("Choisir le dossier de synchronisation");
    if (path) await sync.chooseFolder(path);
  }

  async function stop() {
    if (!sync) return;
    const ok = await confirmDialog("Tes données restent sur cet appareil. Le fichier du dossier n'est pas supprimé.",
                                   { title: "Arrêter la synchronisation ?", okLabel: "Arrêter" });
    if (ok) sync.stop();
  }
</script>

<div class="col">
  {#if sync}
    <Card>
      <div class="title">Dossier partagé</div>
      {#if sync.folder}
        <div class="line"><span>Dossier</span><span class="secondary truncate" title={sync.folder}>{sync.folderName}</span></div>
      {/if}
      <div class="row">
        <button class="btn" onclick={pick}><Icon name="folder.badge.plus" size={14} />Choisir le dossier…</button>
        {#if hasICloud && !sync.isConfigured}
          <button class="btn" onclick={() => sync.useDefaultFolder()}><Icon name="icloud" size={14} />Utiliser iCloud Drive</button>
        {/if}
        {#if sync.isConfigured}
          <button class="btn danger" onclick={stop}><Icon name="xmark.icloud" size={14} />Arrêter la synchronisation</button>
        {/if}
      </div>
      <p class="caption">Choisis un dossier dans iCloud Drive : le Mac et le PC y partagent tes données.</p>
      {#if !sync.isConfigured && sync.lastError}
        <p class="caption negative">{sync.lastError}</p>
      {/if}
    </Card>

    {#if sync.isConfigured}
      <Card>
        <div class="title">État</div>
        <div class="row">
          <button class="btn" disabled={sync.isSyncing} onclick={() => sync.syncNow()}>
            <Icon name="arrow.triangle.2.circlepath" size={14} />Synchroniser maintenant
          </button>
          {#if sync.isSyncing}<span class="caption">…</span>{/if}
        </div>
        <div class="line">
          <span>Dernière synchro</span>
          <span class="secondary">{sync.lastSync ? relative(sync.lastSync, now) : "Jamais"}</span>
        </div>
        {#if sync.lastError}
          <p class="caption negative">{sync.lastError}</p>
        {/if}
      </Card>
    {/if}
  {:else}
    <p class="secondary">La synchronisation n'est pas disponible.</p>
  {/if}
</div>
