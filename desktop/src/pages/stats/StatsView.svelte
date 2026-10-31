<script lang="ts">
  // Statistiques : période, chiffres clés, budgets, prévision, répartition par catégorie (avec détail des opérations),
  // évolution mensuelle et plus grosses dépenses (StatsView.swift). Graphiques en SVG.
  import { store } from "../../lib/app.svelte";
  import type { Draft } from "../../lib/drafts";
  import { addMonths, startOfMonth, startOfYear } from "../../lib/dates";
  import { euros, mediumDate, monthTitle, percent, shortDate } from "../../lib/format";
  import { resolvedAccountID } from "../../lib/model";
  import {
    categoryTransactions, isNavigable, makeStatsSnapshot, monthStartsWithData, type StatsPeriod, statsPeriodLabel, statsPeriods,
  } from "../../lib/logic/stats";
  import { categoryColor } from "../../lib/theme.svelte";
  import BudgetsCard from "../../ui/BudgetsCard.svelte";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Icon from "../../ui/Icon.svelte";
  import MonthPicker from "../../ui/MonthPicker.svelte";
  import OperationEditor from "../operations/OperationEditor.svelte";
  import ForecastCard from "./ForecastCard.svelte";
  import { monotonePath, niceTicks, ringSlice } from "./chart";

  let { accountID: initialAccountID = null }: { accountID?: string | null } = $props();

  const DRILL_DOWN_LIMIT = 10;

  let period = $state<StatsPeriod>("month");
  let offset = $state(0);
  let showIncomeLine = $state(true);
  /// Compte analysé ; null = tous les comptes.
  // svelte-ignore state_referenced_locally
  let accountID = $state<string | null>(initialAccountID);
  /// Catégories dépliées (opérations visibles) et celles montrées en entier.
  let expanded = $state<Record<string, boolean>>({});
  let fullyShown = $state<Record<string, boolean>>({});
  let draft = $state<Draft | null>(null);

  const transactions = $derived(accountID === null ? store.transactions : store.transactions.filter(t => resolvedAccountID(t) === accountID));
  const stats = $derived(makeStatsSnapshot(transactions, period, offset, id => store.category(id)));
  const monthsWithData = $derived(monthStartsWithData(transactions));
  const selectableAccounts = $derived(store.selectableAccounts);

  function setPeriod(p: StatsPeriod) {
    if (p === period) return;   // comme `onChange(of: period)` : rien ne change si on reclique la même période
    period = p;
    offset = 0;
  }

  /// Pont entre la date choisie dans le sélecteur et le décalage (`offset`) utilisé par les calculs.
  function getMonth(): Date {
    const now = new Date();
    return period === "year" ? addMonths(startOfYear(now), 12 * offset) : addMonths(startOfMonth(now), offset);
  }
  function setMonth(value: Date) {
    const now = new Date();
    offset = period === "year"
      ? value.getFullYear() - now.getFullYear()
      : (value.getFullYear() - now.getFullYear()) * 12 + (value.getMonth() - now.getMonth());
  }

  const periodTitle = $derived(
    period === "month" ? monthTitle(stats.start) : period === "year" ? String(stats.start.getFullYear())
    : period === "threeMonths" ? "3 derniers mois" : "Toutes les données");

  // MARK: Donut

  const D = 180;
  const slices = $derived.by(() => {
    const total = stats.categories.reduce((n, c) => n + c.amountCents, 0);
    let angle = 0;
    return stats.categories.map(item => {
      const sweep = total > 0 ? (item.amountCents / total) * Math.PI * 2 : 0;
      const path = ringSlice(D / 2, D / 2, (D / 2) * 0.62, D / 2, angle, angle + sweep, 1.5, 1.5);
      angle += sweep;
      return { id: item.id, path, color: categoryColor(item.category.colorIndex) };
    });
  });

  // MARK: Évolution mensuelle

  const H = 200;
  const margin = { top: 8, right: 6, bottom: 22, left: 40 };
  let chartWidth = $state(600);
  const plotW = $derived(Math.max(60, chartWidth - margin.left - margin.right));
  const plotH = H - margin.top - margin.bottom;
  const narrowMonth = new Intl.DateTimeFormat("fr-FR", { month: "narrow" });
  const compactFmt = new Intl.NumberFormat("fr-FR", { notation: "compact", maximumFractionDigits: 1 });

  const monthly = $derived.by(() => {
    const months = stats.months;
    const band = plotW / months.length;
    const index = new Map(months.map((m, i) => [m.getTime(), i]));
    const stacks = months.map(() => [] as { id: string; amount: number; color: string }[]);
    for (const item of stats.monthlyExpenses) {
      const i = index.get(item.month.getTime());
      if (i !== undefined) stacks[i].push({ id: item.id, amount: item.amountCents / 100, color: categoryColor(item.category.colorIndex) });
    }
    const income = stats.monthlyIncome.map(m => m.amountCents / 100);
    const maxValue = Math.max(0, ...stacks.map(s => s.reduce((n, x) => n + x.amount, 0)), ...(showIncomeLine ? income : [0]));
    const ticks = niceTicks(0, maxValue > 0 ? maxValue : 1);
    const hi = ticks[ticks.length - 1];
    const y = (v: number) => margin.top + plotH * (1 - v / hi);
    const x = (i: number) => margin.left + band * (i + 0.5);
    const bars = stacks.map((stack, i) => {
      let acc = 0;
      return stack.map(seg => {
        const top = y(acc + seg.amount);
        const bottom = y(acc);
        acc += seg.amount;
        return { ...seg, x: x(i) - band * 0.3, y: top, h: Math.max(0.5, bottom - top), w: band * 0.6 };
      });
    });
    const step = months.length > 12 ? 3 : 1;
    return { bars, ticks, y, x, band, step, incomePath: monotonePath(income.map((v, i) => ({ x: x(i), y: y(v) }))) };
  });
</script>

{#snippet sectionTitle(text: string)}<span class="title">{text}</span>{/snippet}
{#snippet noExpenses()}<span>Aucune dépense sur cette période.</span>{/snippet}

<div class="page" style:max-width="720px">
  <div class="header">
    <div class="segmented" role="tablist" aria-label="Période">
      {#each statsPeriods as p (p)}
        <button type="button" role="tab" aria-selected={period === p} class:selected={period === p} onclick={() => setPeriod(p)}>
          {statsPeriodLabel[p]}
        </button>
      {/each}
    </div>

    <!-- Filtre par compte, seulement s'il y en a plusieurs -->
    {#if selectableAccounts.length > 1}
      <select class="field account caption" aria-label="Compte" bind:value={accountID}>
        <option value={null}>Tous les comptes</option>
        {#each selectableAccounts as account (account.id)}
          <option value={account.id}>{account.name}</option>
        {/each}
      </select>
    {/if}

    {#if isNavigable(period)}
      <MonthPicker bind:month={getMonth, setMonth} mode={period === "year" ? "year" : "month"} {monthsWithData} />
    {:else}
      <span class="title">{periodTitle}</span>
    {/if}
  </div>

  {#if stats.hasData}
    <!-- Chiffres clés -->
    <Card>
      <span class="caption">Dépensé</span>
      <div class="line">
        <span class="large-amount">{euros(stats.expensesCents)}</span>
        {#if stats.expenseChange !== null}
          {@const up = stats.expenseChange > 0}
          <span class="caption row tight" style:color={up ? "var(--negative)" : "var(--positive)"}>
            <Icon name={up ? "arrow.up.right" : "arrow.down.right"} size={13} color={up ? "var(--negative)" : "var(--positive)"} />
            {percent(Math.abs(stats.expenseChange))} vs période préc. à date
          </span>
        {:else}
          <span class="caption tertiary">Pas de période préc.</span>
        {/if}
      </div>
      <hr class="separator" />
      <div class="figures">
        <div class="figure"><span class="caption">Revenus</span><span class="amount truncate" style:color="var(--positive)">{euros(stats.incomeCents)}</span></div>
        <div class="figure"><span class="caption">Solde</span><span class="amount truncate" style:color={stats.balanceCents >= 0 ? "var(--positive)" : "var(--negative)"}>{euros(stats.balanceCents)}</span></div>
        <div class="figure"><span class="caption">Moy. / mois</span><span class="amount truncate">{euros(stats.averagePerMonthCents)}</span></div>
      </div>
    </Card>

    {#if period === "month"}
      <BudgetsCard month={stats.start} detailed />
      {#if offset === 0 && accountID === null}<ForecastCard />{/if}
    {/if}

    <!-- Par catégorie -->
    <Card>
      {@render sectionTitle("Par catégorie")}
      {#if stats.categories.length === 0}
        {@render noExpenses()}
      {:else}
        <div class="donut" style:width="{D}px" style:height="{D}px">
          <svg width={D} height={D} viewBox="0 0 {D} {D}" role="img" aria-label="Répartition des dépenses par catégorie">
            {#each slices as slice (slice.id)}
              {#if slice.path}
                <path d={slice.path} fill={slice.color} stroke={slice.color} stroke-width="3" stroke-linejoin="round" fill-rule="evenodd" />
              {/if}
            {/each}
          </svg>
          <div class="donut-center">
            <span class="caption">Total</span>
            <span class="amount">{euros(stats.expensesCents)}</span>
          </div>
        </div>

        <div class="col">
          {#each stats.categories as item (item.id)}
            {@const isOpen = !!expanded[item.id]}
            {@const color = categoryColor(item.category.colorIndex)}
            <div class="col">
              <button type="button" class="cat" aria-expanded={isOpen} onclick={() => (expanded = { ...expanded, [item.id]: !isOpen })}>
                <CategoryBadge icon={item.category.icon} colorIndex={item.category.colorIndex} />
                <div class="cat-body">
                  <div class="cat-head">
                    <span class="grow truncate">{item.category.label}</span>
                    <span class="amount">{euros(item.amountCents)}</span>
                    <span class="caption share">{percent(item.share)}</span>
                    <span class="chevron" class:open={isOpen}><Icon name="chevron.right" size={12} color="var(--text-tertiary)" /></span>
                  </div>
                  <div class="bar"><div style:width="{item.share * 100}%" style:background={color}></div></div>
                </div>
              </button>

              {#if isOpen}
                {@const all = categoryTransactions(item.id, transactions, stats.start, stats.end)}
                {@const showAll = !!fullyShown[item.id]}
                <div class="col tight drill">
                  {#each showAll ? all : all.slice(0, DRILL_DOWN_LIMIT) as t (t.id)}
                    <button type="button" class="drill-row" onclick={() => (draft = { transaction: t, isNew: false })}>
                      <span class="caption date">{shortDate(t.date)}</span>
                      <span class="grow truncate">{t.note === "" ? item.category.label : t.note}</span>
                      <span class="amount">{euros(t.amountCents)}</span>
                    </button>
                  {/each}
                  {#if all.length > DRILL_DOWN_LIMIT}
                    <button type="button" class="link caption" onclick={() => (fullyShown = { ...fullyShown, [item.id]: !showAll })}>
                      {showAll ? "Réduire" : `Voir les ${all.length - DRILL_DOWN_LIMIT} autres`}
                    </button>
                  {/if}
                </div>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </Card>

    <!-- Évolution mensuelle -->
    <Card>
      <div class="line center">
        {@render sectionTitle("Évolution mensuelle")}
        <label class="row tight caption"><input type="checkbox" bind:checked={showIncomeLine} />Revenus</label>
      </div>
      <div class="chart" bind:clientWidth={chartWidth}>
        <svg width={chartWidth} height={H} role="img" aria-label="Dépenses par mois et par catégorie">
          {#each monthly.ticks as tick (tick)}
            <line x1={margin.left} x2={margin.left + plotW} y1={monthly.y(tick)} y2={monthly.y(tick)} stroke="var(--separator)" />
            <text x={margin.left - 6} y={monthly.y(tick) + 3} text-anchor="end" class="axis">{compactFmt.format(tick)}</text>
          {/each}
          {#each monthly.bars as stack, i (i)}
            {#each stack as seg (seg.id)}
              <rect x={seg.x} y={seg.y} width={seg.w} height={seg.h} fill={seg.color} />
            {/each}
          {/each}
          {#if showIncomeLine}
            <path d={monthly.incomePath} fill="none" stroke="var(--positive)" stroke-width="1.5" stroke-dasharray="4 3" />
          {/if}
          {#each stats.months as m, i (m.getTime())}
            {#if i % monthly.step === 0}
              <text x={monthly.x(i)} y={H - 6} text-anchor="middle" class="axis">{narrowMonth.format(m)}</text>
            {/if}
          {/each}
        </svg>
      </div>
    </Card>

    <!-- Plus grosses dépenses -->
    <Card>
      {@render sectionTitle("Plus grosses dépenses")}
      {#if stats.topExpenses.length === 0}
        {@render noExpenses()}
      {:else}
        {#each stats.topExpenses as t (t.id)}
          {@const category = store.categoryOf(t)}
          <div class="row">
            <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} />
            <div class="col tight grow">
              <span class="truncate">{t.note === "" ? category.label : t.note}</span>
              <span class="caption">{mediumDate(t.date)}</span>
            </div>
            <span class="amount">{euros(t.amountCents)}</span>
          </div>
        {/each}
      {/if}
    </Card>
  {:else}
    <div class="empty-state">
      <Icon name="chart.pie" size={34} color="var(--text-tertiary)" strokeWidth={1.5} />
      <span class="title">Aucune donnée</span>
      <span class="secondary">Ajoutez des transactions pour voir vos statistiques ici.</span>
    </div>
  {/if}
</div>

{#if draft}<OperationEditor {draft} onclose={() => (draft = null)} />{/if}

<style>
  .header { display: flex; flex-direction: column; align-items: center; gap: var(--spacing); }
  .header .segmented { align-self: stretch; }
  .header .segmented button { flex: 1; }
  .account { height: 24px; }
  .figures { display: flex; gap: var(--spacing); }
  .figure { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .donut { position: relative; align-self: center; flex-shrink: 0; }
  .donut-center { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; pointer-events: none; }
  .cat { display: flex; align-items: center; gap: var(--spacing); width: 100%; border: none; background: transparent; padding: 0; color: inherit; text-align: left; font: inherit; }
  .cat-body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
  .cat-head { display: flex; align-items: center; gap: var(--spacing); }
  .grow { flex: 1; min-width: 0; }
  .share { width: 40px; text-align: right; }
  .chevron { display: inline-flex; transition: transform 0.2s; }
  .chevron.open { transform: rotate(90deg); }
  .bar { height: 4px; border-radius: calc(var(--radius-small) / 2); background: var(--surface-secondary); overflow: hidden; }
  .bar > div { height: 100%; }
  .drill { padding-left: calc(var(--icon-size) + var(--spacing)); }
  .drill-row { display: flex; align-items: baseline; gap: var(--spacing); width: 100%; border: none; background: transparent; padding: 0; color: inherit; text-align: left; font: inherit; }
  .drill-row:hover { background: var(--surface-secondary); }
  .date { width: 56px; flex-shrink: 0; }
  .link { align-self: flex-start; border: none; background: transparent; padding: 0; color: var(--accent); }
  .center { align-items: center; }
  .chart { width: 100%; }
  .chart svg { display: block; }
  .axis { font-size: var(--caption); fill: var(--text-secondary); }
  .empty-state { display: flex; flex-direction: column; align-items: center; gap: var(--spacing); padding: calc(var(--padding) * 3) 0; text-align: center; }
</style>
