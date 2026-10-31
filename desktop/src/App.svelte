<script lang="ts">
  // Écran racine : barre latérale et page affichée, feuilles globales (réglages, assistant de démarrage,
  // revue des repas, import d'un relevé déposé), tâches du lancement et raccourcis globaux. Port de RootView.swift.
  import { onMount } from "svelte";
  import { nav, navigate, store } from "./lib/app.svelte";
  import { prefs } from "./lib/prefs.svelte";
  import { appPaths, inTauri } from "./lib/platform";
  import { backupIfNeeded } from "./lib/logic/backup";
  import { generateDueRecurringOperations } from "./lib/logic/recurring";
  import { generateDueMeals, needsMealReview } from "./lib/logic/meals";
  import { refreshRates } from "./lib/logic/rates";
  import { startSync } from "./lib/sync/coordinator.svelte";
  import { runBench } from "./lib/bench";
  import Sidebar from "./Sidebar.svelte";
  import Icon from "./ui/Icon.svelte";
  import DashboardPage from "./pages/dashboard/DashboardPage.svelte";
  import OperationsPage from "./pages/operations/OperationsPage.svelte";
  import AccountsPage from "./pages/accounts/AccountsPage.svelte";
  import PlanningPage from "./pages/planning/PlanningPage.svelte";
  import StatsView from "./pages/stats/StatsView.svelte";
  import SettingsPage from "./pages/settings/SettingsPage.svelte";
  import Onboarding from "./pages/onboarding/Onboarding.svelte";
  import MealReviewSheet from "./pages/accounts/MealReviewSheet.svelte";
  import ImportStatementSheet from "./pages/import/ImportStatementSheet.svelte";
  import ShortcutsSheet from "./pages/operations/ShortcutsSheet.svelte";

  /// Extensions de relevés acceptées par glisser-déposer.
  const statementExtensions = ["csv", "ofx", "qfx", "txt", "xlsx", "xls"];

  let mealReviewAccountID = $state<string | null>(null);
  let droppedStatement = $state<string | null>(null);
  let isDropTargeted = $state(false);
  let showShortcuts = $state(false);
  /// Mode mesure : pas d'assistant, de revue des repas ni de synchro.
  const benchDir = appPaths().benchDir;

  onMount(() => {
    // Au lancement : sauvegarde du jour, puis échéances récurrentes passées et repas Izly.
    void (async () => {
      await backupIfNeeded(store);
      generateDueRecurringOperations(store);
      generateDueMeals(store);
      // Revue hebdomadaire des repas (pas pendant l'assistant de démarrage)
      if (benchDir) { await runBench(store, benchDir, (page) => navigate(page), 0); return; }
      if (prefs.onboardingCompleted.value) mealReviewAccountID = needsMealReview(store)?.id ?? null;
      startSync(store);
      await refreshRates(store);
    })();

    if (!inTauri) return;
    let unlisten: (() => void) | undefined;
    void import("@tauri-apps/api/webview").then(async ({ getCurrentWebview }) => {
      unlisten = await getCurrentWebview().onDragDropEvent((event) => {
        const p = event.payload;
        if (p.type === "over" || p.type === "enter") isDropTargeted = prefs.onboardingCompleted.value;
        else if (p.type === "leave") isDropTargeted = false;
        else if (p.type === "drop") {
          isDropTargeted = false;
          const path = p.paths.find(x => statementExtensions.includes(x.split(".").pop()?.toLowerCase() ?? ""));
          if (path && prefs.onboardingCompleted.value) droppedStatement = path;
        }
      });
    });
    return () => unlisten?.();
  });

  /// Un champ de texte a le focus : Ctrl/Cmd+Z y annule la saisie, pas la dernière action.
  const isEditing = (el: Element | null) =>
    el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || (el instanceof HTMLElement && el.isContentEditable);

  function onkeydown(e: KeyboardEvent) {
    const mod = e.metaKey || e.ctrlKey;
    if (!mod) return;
    const key = e.key.toLowerCase();
    if (key === ",") { e.preventDefault(); nav.settingsOpen = true; return; }
    // Aide des raccourcis clavier (⌘/ sur Mac, Ctrl+/ sur Windows)
    if (key === "/") { e.preventDefault(); showShortcuts = true; return; }
    if (isEditing(document.activeElement)) return;
    if (key === "z" && !e.shiftKey) { e.preventDefault(); store.undo(); }
    else if ((key === "z" && e.shiftKey) || key === "y") { e.preventDefault(); store.redo(); }
  }
</script>

<svelte:window {onkeydown} />

<div class="app">
  <Sidebar />
  <main class="detail">
    {#if nav.page === "dashboard"}<DashboardPage />
    {:else if nav.page === "operations"}<OperationsPage />
    {:else if nav.page === "accounts"}<AccountsPage />
    {:else if nav.page === "planning"}<PlanningPage />
    {:else}<StatsView accountID={null} />
    {/if}
  </main>
</div>

{#if store.errorMessage}
  <div class="error" role="alert">
    <Icon name="exclamationmark.triangle.fill" size={15} color="var(--warning)" />
    <span>{store.errorMessage}</span>
    <button type="button" class="btn small" onclick={() => (store.errorMessage = null)}>OK</button>
  </div>
{/if}

{#if showShortcuts}<ShortcutsSheet onclose={() => (showShortcuts = false)} />{/if}

{#if nav.settingsOpen}<SettingsPage onclose={() => (nav.settingsOpen = false)} />{/if}

{#if !prefs.onboardingCompleted.value && !benchDir}
  <Onboarding onfinish={() => (prefs.onboardingCompleted.value = true)} />
{:else if mealReviewAccountID}
  <MealReviewSheet accountID={mealReviewAccountID} onclose={() => (mealReviewAccountID = null)} />
{:else if droppedStatement}
  <ImportStatementSheet path={droppedStatement} onclose={() => (droppedStatement = null)} />
{/if}

{#if isDropTargeted}
  <div class="drop-veil">
    <div class="drop-box col">
      <Icon name="square.and.arrow.down.on.square" size={34} color="var(--accent)" strokeWidth={1.5} />
      <span class="title">Dépose ton relevé pour l’importer</span>
    </div>
  </div>
{/if}

<style>
  .app { display: flex; height: 100vh; }
  .detail { flex: 1; min-width: 0; overflow: auto; background: linear-gradient(to bottom, var(--bg-top), var(--bg-bottom)); }
  .error {
    position: fixed; left: 50%; bottom: 16px; transform: translateX(-50%); z-index: 200;
    display: flex; align-items: center; gap: 10px; max-width: min(640px, calc(100vw - 32px));
    padding: 10px 12px; border-radius: var(--radius); background: var(--surface);
    box-shadow: 0 8px 30px rgba(0, 0, 0, 0.2), 0 0 0 1px var(--separator);
  }
  .drop-veil {
    position: fixed; inset: 0; z-index: 300; pointer-events: none; display: flex; align-items: center; justify-content: center;
    background: color-mix(in srgb, var(--background) 80%, transparent);
  }
  .drop-box {
    align-items: center; padding: calc(var(--padding) * 2); background: var(--surface); border-radius: var(--radius);
    border: 2px dashed var(--accent);
  }
</style>
