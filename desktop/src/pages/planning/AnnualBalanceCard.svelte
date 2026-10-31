<script lang="ts">
  // Équilibre à l'année : un dépassement d'un mois a-t-il été rattrapé les mois suivants ? (BudgetAnnualCard.swift)
  // Graphique en SVG (écart mensuel en barres, cumul en courbe), carte de chaleur et légende.
  import { store } from "../../lib/app.svelte";
  import { addMonths } from "../../lib/dates";
  import { budgetEuros } from "../../lib/logic/budgets";
  import { type AnnualBudgetCell, type AnnualBudgetRow, type AnnualBudgetTrend, annualBudgetBalance, trendLabel } from "../../lib/logic/planning";
  import { monotonePath, niceTicks } from "../stats/chart";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";

  let { year }: { year: Date } = $props();

  const balance = $derived(annualBudgetBalance(store, year));
  const yearNumber = $derived(balance.year.getFullYear());
  const total = $derived(balance.total);

  // MARK: Formats

  const monthFmt = (options: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat("fr-FR", options);
  const shortMonthFmt = monthFmt({ month: "short" });
  const longMonthFmt = monthFmt({ month: "long" });
  const shortMonth = (d: Date) => shortMonthFmt.format(d);
  const longMonth = (d: Date) => longMonthFmt.format(d);
  const wholeFmt = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 0 });
  const tenthFmt = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 });

  /// Montant compact (en centimes → « +12 », « −45 », « 1,2k »).
  function compact(cents: number, signed: boolean): string {
    const number = cents / 100;
    const magnitude = Math.abs(number);
    const body = magnitude >= 1000 ? tenthFmt.format(magnitude / 1000) + "k" : wholeFmt.format(magnitude);
    if (number < 0 && body !== "0") return "−" + body;
    return (signed && number > 0 && body !== "0" ? "+" : "") + body;
  }

  const signedEuros = (cents: number) => (cents < 0 ? "−" + budgetEuros(-cents) : cents > 0 ? "+" + budgetEuros(cents) : budgetEuros(cents));

  // MARK: Synthèse

  const summary = $derived.by(() => {
    const value = total.balance;
    const sentence = value < 0 ? `${budgetEuros(-value)} à rattraper`
      : value === 0 ? "À l'équilibre sur l'année" : `+${budgetEuros(value)} d'avance sur l'année`;
    const color = value < 0 ? "var(--negative)" : value === 0 ? "var(--text-primary)" : "var(--positive)";
    const exceeded = total.exceededMonths;
    return { sentence, color, detail: `${total.counted.length} mois comptés · ${exceeded} mois dépassé${exceeded > 1 ? "s" : ""}` };
  });

  // MARK: Graphique

  const H = 180;
  const margin = { top: 22, right: 8, bottom: 22, left: 40 };
  let width = $state(600);
  const plotW = $derived(Math.max(60, width - margin.left - margin.right));
  const plotH = H - margin.top - margin.bottom;
  const band = $derived(plotW / 12);

  const chart = $derived.by(() => {
    const counted = total.counted;
    const running = total.runningBalance;
    const values = [0, ...counted.map(c => c.difference / 100), ...running.map(p => p.balance / 100)];
    const ticks = niceTicks(Math.min(...values), Math.max(...values));
    const lo = ticks[0];
    const hi = ticks[ticks.length - 1];
    const y = (v: number) => margin.top + plotH * (1 - (v - lo) / (hi - lo));
    const monthIndex = (d: Date) => (d.getFullYear() - balance.year.getFullYear()) * 12 + d.getMonth();
    const x = (d: Date) => margin.left + band * (monthIndex(d) + 0.5);
    const points = running.map(p => ({ x: x(p.month), y: y(p.balance / 100) }));
    const current = counted.find(c => c.isCurrent);
    return { counted, ticks, y, x, points, path: monotonePath(points), zero: y(0), currentX: current ? x(current.month) : null };
  });

  // MARK: Carte de chaleur

  function cellColor(cell: AnnualBudgetCell): string {
    if (!cell.isCounted) return "var(--surface-secondary)";
    const tint = cell.difference >= 0 ? "var(--positive)" : "var(--negative)";
    const ratio = cell.planned > 0 ? Math.min(1, Math.abs(cell.difference / cell.planned)) : cell.spent > 0 ? 1 : 0;
    return `color-mix(in srgb, ${tint} ${(0.12 + 0.5 * ratio) * 100}%, transparent)`;
  }

  const trendColor: Record<AnnualBudgetTrend, string> = { onTrack: "var(--positive)", recovered: "var(--warning)", behind: "var(--negative)" };
  const balanceColor = (v: number) => (v < 0 ? "var(--negative)" : v > 0 ? "var(--positive)" : "var(--text-secondary)");

  function cellLabel(name: string, cell: AnnualBudgetCell): string {
    const month = longMonth(cell.month);
    const text = cell.isCounted
      ? `${name}, ${month}, ${signedEuros(cell.difference)}, budget ${budgetEuros(cell.planned)}, dépensé ${budgetEuros(cell.spent)}`
      : `${name}, ${month}, ${cell.isFuture ? "à venir, " : ""}budget ${budgetEuros(cell.planned)}`;
    return text + (cell.isCurrent ? ", mois en cours" : "");
  }
</script>

{#snippet heatRow(row: AnnualBudgetRow)}
  {@const name = row.category?.label ?? "Total"}
  <div class="hrow">
    <div class="name">
      {#if row.category}<CategoryBadge icon={row.category.icon} colorIndex={row.category.colorIndex} size={24} />{/if}
      <span class="truncate" class:title={!row.category}>{name}</span>
    </div>
    {#each row.cells as cell (cell.month.getTime())}
      <div class="cell" class:current={cell.isCurrent} style:background={cellColor(cell)}
           title={`${longMonth(cell.month)} · Budget ${budgetEuros(cell.planned)} · Dépensé ${budgetEuros(cell.spent)}`}
           role="img" aria-label={cellLabel(name, cell)}>
        {#if cell.isCounted}
          <span class="caption primary">{compact(cell.difference, true)}</span>
        {:else if cell.planned > 0}
          <span class="caption tertiary">{compact(cell.planned, false)}</span>
        {/if}
      </div>
    {/each}
    <span class="amount cumul" style:color={balanceColor(row.balance)} title={`Cumul de l'année : ${signedEuros(row.balance)}`}
          aria-label={`${name}, cumul de l'année ${signedEuros(row.balance)}`}>{compact(row.balance, true)}</span>
    <div class="trend"><span class="badge caption" style:--c={trendColor[row.trend]}>{trendLabel[row.trend]}</span></div>
  </div>
{/snippet}

<Card>
  <span class="title">Équilibre {yearNumber}</span>
  {#if balance.rows.length === 0}
    <span class="secondary">Aucune catégorie n'a de budget cette année. Définis des budgets pour suivre ton équilibre.</span>
  {:else}
    <div class="col tight">
      <span class="amount" style:color={summary.color}>{summary.sentence}</span>
      <span class="caption">{summary.detail}</span>
    </div>

    {#if total.counted.length > 0}
      <div class="chart" bind:clientWidth={width}>
        <svg {width} height={H} role="img" aria-label="Graphique de l'écart mensuel et du cumul de l'année">
          {#each chart.ticks as tick (tick)}
            <line x1={margin.left} x2={margin.left + plotW} y1={chart.y(tick)} y2={chart.y(tick)} stroke="var(--separator)" stroke-width="1" />
            <text x={margin.left - 6} y={chart.y(tick) + 3} text-anchor="end" class="axis tertiary-fill">{compact(tick * 100, false)}</text>
          {/each}
          <line x1={margin.left} x2={margin.left + plotW} y1={chart.zero} y2={chart.zero} stroke="var(--text-tertiary)" stroke-width="1" />
          {#each Array.from({ length: 12 }, (_, i) => addMonths(balance.year, i)) as m (m.getTime())}
            <text x={chart.x(m)} y={H - 6} text-anchor="middle" class="axis"
                  class:accent-fill={total.cells.find(c => c.month.getTime() === m.getTime())?.isCurrent}>{shortMonth(m)}</text>
          {/each}
          {#if chart.currentX !== null}
            <line x1={chart.currentX} x2={chart.currentX} y1={margin.top} y2={margin.top + plotH} stroke="var(--accent)" stroke-opacity="0.35" stroke-dasharray="3 3" />
            <text x={chart.currentX} y={margin.top - 8} text-anchor="middle" class="axis">en cours</text>
          {/if}
          {#each chart.counted as cell (cell.month.getTime())}
            {@const top = chart.y(Math.max(0, cell.difference / 100))}
            {@const bottom = chart.y(Math.min(0, cell.difference / 100))}
            <rect x={chart.x(cell.month) - band * 0.3} y={top} width={band * 0.6} height={Math.max(1, bottom - top)}
                  rx="3" fill={cell.difference >= 0 ? "var(--positive)" : "var(--negative)"} />
          {/each}
          <path d={chart.path} fill="none" stroke="var(--accent)" stroke-width="2" />
          {#each chart.points as p, i (i)}
            <circle cx={p.x} cy={p.y} r="3" fill="var(--accent)" />
          {/each}
        </svg>
      </div>
    {/if}

    <div class="heat">
      <div class="hrow header caption">
        <div class="name"></div>
        {#each total.cells as cell (cell.month.getTime())}
          <span class="mh truncate" style:color={cell.isCurrent ? "var(--accent)" : undefined}>{shortMonth(cell.month)}</span>
        {/each}
        <span class="cumul">Cumul</span>
        <span class="trend">Tendance</span>
      </div>
      {#each balance.rows as row (row.id)}
        {@render heatRow(row)}
        {#if row.catchUpPerMonth !== null && row.trend === "behind"}
          <span class="caption catch">≤ {budgetEuros(row.catchUpPerMonth)}/mois jusqu'en décembre pour rattraper</span>
        {/if}
      {/each}
      <hr class="separator" />
      {@render heatRow(total)}
    </div>

    <div class="legend caption">
      <span class="row tight"><i style:background="color-mix(in srgb, var(--positive) 45%, transparent)"></i>Économie</span>
      <span class="row tight"><i style:background="color-mix(in srgb, var(--negative) 45%, transparent)"></i>Dépassement</span>
      <span class="row tight"><i style:background="var(--surface-secondary)"></i>Non compté / à venir (budget prévu)</span>
      <span class="row tight"><i class="ring"></i>En cours</span>
    </div>
  {/if}
</Card>

<style>
  .chart { width: 100%; }
  .chart svg { display: block; }
  .axis { font-size: var(--caption); fill: var(--text-secondary); }
  .axis.tertiary-fill { fill: var(--text-tertiary); }
  .axis.accent-fill { fill: var(--accent); }
  .primary { color: var(--text-primary); }
  .heat { overflow-x: auto; display: flex; flex-direction: column; gap: 4px; padding: 2px 0; }
  .heat > * { flex-shrink: 0; }
  .hrow { display: flex; align-items: center; gap: 3px; width: max-content; }
  .name { width: 150px; display: flex; align-items: center; gap: 8px; min-width: 0; }
  .cell {
    width: 46px; height: 30px; border-radius: calc(var(--radius-small) / 2); display: flex; align-items: center; justify-content: center;
    box-sizing: border-box; flex-shrink: 0;
  }
  .cell.current { box-shadow: inset 0 0 0 1.5px var(--accent); }
  .mh { width: 46px; text-align: center; }
  .cumul { width: 70px; text-align: right; flex-shrink: 0; }
  .trend { width: 96px; text-align: center; flex-shrink: 0; }
  .badge {
    display: inline-block; padding: 3px 8px; border-radius: 999px; color: var(--c); white-space: nowrap;
    background: color-mix(in srgb, var(--c) 15%, transparent);
  }
  .catch { padding-left: 153px; }
  .legend { display: flex; flex-wrap: wrap; gap: 14px; }
  .legend i { width: 12px; height: 12px; border-radius: 3px; display: inline-block; }
  .legend i.ring { box-shadow: inset 0 0 0 1.5px var(--accent); }
</style>
