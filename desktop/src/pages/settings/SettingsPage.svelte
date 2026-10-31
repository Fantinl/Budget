<script lang="ts">
  // Réglages : plein écran au-dessus de l'app (la fenêtre Réglages de l'app Mac). Port de SettingsView.swift.
  // Accueil = liste des sections ; `nav.settingsSection` ouvre directement une section
  // (« categories », « tags », « quick », « recurring », « data », « sync », « shortcuts »).
  import { nav, store } from "../../lib/app.svelte";
  import { prefs } from "../../lib/prefs.svelte";
  import { setDefaultAccount } from "../../lib/logic/accounts";
  import Icon from "../../ui/Icon.svelte";
  import Group from "./Group.svelte";
  import SettingsCategories from "./SettingsCategories.svelte";
  import SettingsTags from "./SettingsTags.svelte";
  import SettingsQuickExpenses from "./SettingsQuickExpenses.svelte";
  import SettingsData from "./SettingsData.svelte";
  import SettingsAppearance from "./SettingsAppearance.svelte";
  import StudentProfileSection from "./StudentProfileSection.svelte";
  import SyncSettings from "./SyncSettings.svelte";
  import RecurringView from "../recurring/RecurringView.svelte";
  import ShortcutsSheet from "../operations/ShortcutsSheet.svelte";

  let { onclose }: { onclose: () => void } = $props();

  type Section = "categories" | "tags" | "quick" | "recurring" | "data" | "sync";
  const entries: { id: Section; title: string; symbol: string }[] = [
    { id: "categories", title: "Catégories", symbol: "tag" },
    { id: "tags", title: "Tags", symbol: "number" },
    { id: "quick", title: "Dépenses rapides", symbol: "bolt" },
    { id: "recurring", title: "Opérations récurrentes", symbol: "arrow.triangle.2.circlepath" },
    { id: "data", title: "Données", symbol: "externaldrive" },
    { id: "sync", title: "Synchronisation", symbol: "icloud" },
  ];

  // svelte-ignore state_referenced_locally
  let section = $state<Section | null>(entries.some(e => e.id === nav.settingsSection) ? (nav.settingsSection as Section) : null);
  let showShortcuts = $state(nav.settingsSection === "shortcuts");

  const title = $derived(entries.find(e => e.id === section)?.title ?? "Réglages");

  function back() {
    section = null;
    nav.settingsSection = null;
  }

  function onkeydown(e: KeyboardEvent) {
    if (e.key !== "Escape" || document.querySelector('[role="dialog"]')) return;
    if (section) back(); else onclose();
  }

  function restartOnboarding() {
    prefs.onboardingCompleted.value = false;
    onclose();
  }
</script>

<svelte:window {onkeydown} />

<div class="overlay" role="region" aria-label="Réglages">
  <header>
    {#if section}
      <button type="button" class="btn plain" onclick={back}><Icon name="chevron.left" size={15} /> Réglages</button>
    {:else}
      <span class="side"></span>
    {/if}
    <h1 class="title">{title}</h1>
    <span class="side right"><button type="button" class="btn" onclick={onclose}>Terminé</button></span>
  </header>

  <div class="scroll">
    <div class="body" class:wide={section === "recurring" || section === "sync"}>
      {#if section === "categories"}<SettingsCategories />
      {:else if section === "tags"}<SettingsTags />
      {:else if section === "quick"}<SettingsQuickExpenses />
      {:else if section === "recurring"}<RecurringView />
      {:else if section === "data"}<SettingsData />
      {:else if section === "sync"}<SyncSettings />
      {:else}
        <Group>
          {#each entries as entry (entry.id)}
            <button type="button" class="nav" onclick={() => (section = entry.id)}>
              <Icon name={entry.symbol} size={17} color="var(--accent)" />
              <span class="grow">{entry.title}</span>
              <Icon name="chevron.right" size={15} color="var(--text-tertiary)" />
            </button>
          {/each}
        </Group>

        <Group footer="Utilisé pour les nouvelles opérations, les ajouts rapides et les récurrentes sans compte précis.">
          <label class="pick"><span>Compte par défaut</span>
            <select class="field" value={store.defaultAccount.id}
                    onchange={(e) => { const a = store.selectableAccounts.find(x => x.id === e.currentTarget.value); if (a) setDefaultAccount(store, a); }}>
              {#each store.selectableAccounts as account (account.id)}<option value={account.id}>{account.name}</option>{/each}
            </select></label>
        </Group>

        <StudentProfileSection />
        <SettingsAppearance />

        <Group>
          <button type="button" class="nav" onclick={() => (showShortcuts = true)}>
            <Icon name="keyboard" size={17} color="var(--accent)" />
            <span class="grow">Raccourcis clavier</span>
          </button>
        </Group>

        <Group>
          <button type="button" class="nav" onclick={restartOnboarding}>Relancer l’assistant de démarrage</button>
        </Group>
      {/if}
    </div>
  </div>
</div>

{#if showShortcuts}
  <ShortcutsSheet onclose={() => (showShortcuts = false)} />
{/if}

<style>
  .overlay {
    position: fixed; inset: 0; z-index: 90; display: flex; flex-direction: column;
    background: linear-gradient(to bottom, var(--bg-top), var(--bg-bottom)), var(--background);
  }
  header {
    display: grid; grid-template-columns: 1fr auto 1fr; align-items: center; gap: var(--spacing);
    padding: 10px var(--padding); border-bottom: 1px solid var(--separator); background: var(--background);
  }
  h1 { margin: 0; text-align: center; }
  .side { display: flex; }
  .side.right { justify-content: flex-end; }
  .scroll { flex: 1; overflow: auto; }
  .body { max-width: 720px; margin: 0 auto; padding: var(--padding); display: flex; flex-direction: column; gap: var(--spacing); }
  .body.wide { max-width: 1000px; }
  .nav {
    width: 100%; border: none; background: transparent; color: inherit; text-align: left; display: flex; align-items: center; gap: 10px;
  }
  .nav:hover { color: var(--accent); }
  .grow { flex: 1; }
  .pick { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: var(--spacing); }
</style>
