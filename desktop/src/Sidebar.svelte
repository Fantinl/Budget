<script lang="ts">
  // Barre latérale : en-tête (logo, chiffres), sections de l'app, date du jour. Port de SidebarView.swift
  // et SidebarComponents.swift.
  import { nav, navigate, openSettings, store, type Page } from "./lib/app.svelte";
  import { prefs } from "./lib/prefs.svelte";
  import { isEarning, isSpending } from "./lib/model";
  import { totalBalance } from "./lib/logic/accounts";
  import { longDayDate, monthAbbrev, roundEuros } from "./lib/format";
  import { categoryColor } from "./lib/theme.svelte";
  import Icon from "./ui/Icon.svelte";

  const month = $derived(store.transactionsInMonthOf(new Date()));
  const spent = $derived(month.filter(isSpending).reduce((s, t) => s + t.amountCents, 0));
  const earned = $derived(month.filter(isEarning).reduce((s, t) => s + t.amountCents, 0));
  const show = $derived(prefs.sidebarFigures.value);

  const rows: { page: Page; title: string; symbol: string; tint: number }[] = [
    { page: "dashboard", title: "Tableau de bord", symbol: "square.grid.2x2", tint: 1 },
    { page: "operations", title: "Opérations", symbol: "list.bullet", tint: 2 },
    { page: "accounts", title: "Comptes", symbol: "building.columns", tint: 0 },
    { page: "planning", title: "Budget", symbol: "gauge.with.dots.needle.50percent", tint: 4 },
    { page: "stats", title: "Statistiques", symbol: "chart.pie", tint: 3 },
  ];

  function info(page: Page): string | null {
    if (!show) return null;
    // Nombre d'opérations du mois en cours uniquement (« 7 en oct. »)
    if (page === "operations" && prefs.sidebarMonthCount.value && month.length > 0) return `${month.length} en ${monthAbbrev(new Date())}`;
    if (page === "accounts" && prefs.sidebarAccountCount.value) return String(store.activeAccounts.length);
    return null;
  }
</script>

<aside class="sidebar">
  <div class="summary">
    <div class="row">
      <img src="/logo.png" alt="" width="34" height="34" />
      <span class="title">Budget</span>
    </div>
    {#if show && (prefs.sidebarWealth.value || prefs.sidebarSpent.value || prefs.sidebarIncome.value || prefs.sidebarBalance.value)}
      <div class="col tight">
        {#if prefs.sidebarWealth.value}
          <div class="line"><span class="caption tertiary">Patrimoine</span><span class="figure">{roundEuros(totalBalance(store))}</span></div>
        {/if}
        {#if prefs.sidebarSpent.value}
          <div class="line"><span class="caption tertiary">Dépensé ce mois-ci</span><span class="figure secondary">{roundEuros(spent)}</span></div>
        {/if}
        {#if prefs.sidebarIncome.value}
          <div class="line"><span class="caption tertiary">Revenus du mois</span><span class="figure positive">{roundEuros(earned)}</span></div>
        {/if}
        {#if prefs.sidebarBalance.value}
          <div class="line"><span class="caption tertiary">Solde du mois</span>
            <span class="figure" class:negative={earned < spent} class:positive={earned >= spent}>{roundEuros(earned - spent)}</span></div>
        {/if}
      </div>
    {/if}
  </div>

  <nav>
    {#each rows as row (row.page)}
      <button type="button" class="item" class:selected={nav.page === row.page} onclick={() => navigate(row.page)}>
        <span class="tile" style:--tint={categoryColor(row.tint)}><Icon name={row.symbol} size={14} color="var(--on-accent)" strokeWidth={2.4} /></span>
        <span class="truncate">{row.title}</span>
        <span class="spacer"></span>
        {#if info(row.page)}<span class="caption tertiary nums">{info(row.page)}</span>{/if}
      </button>
    {/each}
  </nav>

  <footer class="row">
    <span class="caption tertiary truncate">{longDayDate(new Date())}</span>
    <span class="spacer"></span>
    <button type="button" class="btn plain icon" title="Réglages (Ctrl+,)" aria-label="Réglages" onclick={() => openSettings()}>
      <Icon name="gearshape" size={15} color="var(--text-secondary)" />
    </button>
  </footer>
</aside>

<style>
  .sidebar {
    width: var(--sidebar-width); flex-shrink: 0; display: flex; flex-direction: column;
    background: color-mix(in srgb, var(--surface-secondary) 55%, var(--background));
    border-right: 1px solid var(--separator);
  }
  .summary { padding: var(--spacing) var(--padding); display: flex; flex-direction: column; gap: var(--spacing); }
  .summary img { border-radius: 8px; }
  .figure { font-size: var(--caption); font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
  nav { flex: 1; overflow: auto; padding: 0 8px; display: flex; flex-direction: column; gap: 2px; }
  .item {
    display: flex; align-items: center; gap: var(--spacing); min-height: 34px; padding: 3px 8px;
    border: none; background: transparent; color: var(--text-primary); border-radius: var(--radius-small); text-align: left;
  }
  .item:hover { background: color-mix(in srgb, var(--text-primary) 5%, transparent); }
  .item.selected { background: color-mix(in srgb, var(--accent) 16%, transparent); }
  .tile {
    width: 26px; height: 26px; border-radius: var(--radius-small); flex-shrink: 0;
    display: inline-flex; align-items: center; justify-content: center;
    background: linear-gradient(to bottom, color-mix(in srgb, var(--tint) 80%, white), var(--tint));
  }
  footer { padding: var(--spacing) var(--padding); }
</style>
