<script lang="ts">
  // Synthèse du mois : jauge dépensé / disponible, rythme, compteurs et projection de fin de mois (BudgetSummaryCard.swift).
  import { store } from "../../lib/app.svelte";
  import { startOfMonth } from "../../lib/dates";
  import { percent } from "../../lib/format";
  import { budgetEuros, budgetStatuses, daysRemaining, elapsedFraction, isCurrentMonth, totalsOf } from "../../lib/logic/budgets";
  import { projectedSpending } from "../../lib/logic/planning";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";

  let { month }: { month: Date } = $props();

  type Pace = "ahead" | "watch" | "exceeded";
  const paceInfo: Record<Pace, { message: string; icon: string; color: string }> = {
    ahead: { message: "Tu es en avance sur ton budget", icon: "checkmark.circle.fill", color: "var(--positive)" },
    watch: { message: "Rythme à surveiller", icon: "exclamationmark.triangle.fill", color: "var(--warning)" },
    exceeded: { message: "Budget dépassé", icon: "xmark.octagon.fill", color: "var(--negative)" },
  };

  const isCurrent = $derived(isCurrentMonth(month));
  const isPast = $derived(startOfMonth(month).getTime() < startOfMonth(new Date()).getTime());
  const statuses = $derived(budgetStatuses(store, month));
  const totals = $derived(totalsOf(statuses));
  const elapsed = $derived(elapsedFraction(month));
  const pace = $derived<Pace>(totals.ratio > 1 ? "exceeded" : totals.ratio > elapsed + 0.05 ? "watch" : "ahead");
  const remaining = $derived(totals.remaining);
  const perDay = $derived.by(() => {
    const days = daysRemaining(month);
    return isCurrent && days > 0 && remaining > 0 ? remaining / days : null;
  });
  const tint = $derived(isCurrent ? paceInfo[pace].color : totals.ratio > 1 ? "var(--negative)" : "var(--accent)");
  const counters = $derived([
    { count: statuses.filter(x => x.state === "ok").length, label: "dans le budget", color: "var(--positive)", icon: "checkmark.circle.fill" },
    { count: statuses.filter(x => x.state === "warning").length, label: "à surveiller", color: "var(--warning)", icon: "exclamationmark.triangle.fill" },
    { count: statuses.filter(x => x.state === "exceeded").length, label: "dépassées", color: "var(--negative)", icon: "xmark.octagon.fill" },
  ]);
  const projected = $derived(isCurrent
    ? statuses.reduce((n, x) => n + (projectedSpending(store, x.category, month) ?? x.spent), 0) : 0);
  const diff = $derived(totals.budget - projected);

  // Jauge circulaire (viewBox 130, rayon 58, trait 14)
  const R = 58;
  const C = 2 * Math.PI * R;
  const gaugeRatio = $derived(Math.min(Math.max(totals.ratio, 0), 1));
</script>

<Card>
  {#if statuses.length === 0}
    <div class="col">
      <span class="title row tight"><Icon name="chart.pie" size={15} />Budget du mois</span>
      <span class="secondary">Aucun budget n'est fixé ce mois-ci. Fixe un budget par catégorie plus bas, ou applique les suggestions pour démarrer à partir de tes dépenses habituelles.</span>
    </div>
  {:else}
    <div class="col content">
      <span class="title">Budget du mois</span>

      <div class="top">
        <svg class="gauge-svg" viewBox="0 0 130 130" width="130" height="130" role="img"
             aria-label={`${budgetEuros(totals.spent)} dépensés sur ${budgetEuros(totals.budget)}, soit ${Math.round(totals.ratio * 100)} pour cent.`}>
          <circle cx="65" cy="65" r={R} fill="none" stroke="var(--surface-secondary)" stroke-width="14" />
          <circle cx="65" cy="65" r={R} fill="none" stroke={tint} stroke-width="14" stroke-linecap="round"
                  stroke-dasharray="{gaugeRatio * C} {C}" transform="rotate(-90 65 65)" />
          {#if isCurrent}
            <rect x="63.5" y="-11" width="3" height="22" rx="1.5" fill="var(--text-primary)" transform="rotate({elapsed * 360} 65 65)" />
          {/if}
          <text x="65" y="63" text-anchor="middle" class="gauge-value">{percent(totals.ratio)}</text>
          <text x="65" y="79" text-anchor="middle" class="gauge-caption">dépensé</text>
        </svg>

        <div class="figures">
          {#if isCurrent || isPast || remaining < 0}
            <span class="caption">{remaining >= 0 ? "Reste à dépenser" : "Dépassé de"}</span>
            <span class="large-amount truncate" style:color={remaining >= 0 ? "var(--text-primary)" : "var(--negative)"}>{budgetEuros(Math.abs(remaining))}</span>
          {:else}
            <span class="caption">Prévu ce mois</span>
            <span class="large-amount truncate">{budgetEuros(totals.budget)}</span>
          {/if}
          {#if perDay !== null}<span class="secondary">{budgetEuros(perDay)} / jour possible</span>{/if}
          {#if !isPast && !isCurrent}<span class="caption tertiary">Mois à venir</span>{/if}
        </div>
      </div>

      {#if isCurrent}
        <span class="pace row tight" style:color={paceInfo[pace].color}>
          <Icon name={paceInfo[pace].icon} size={15} color={paceInfo[pace].color} />{paceInfo[pace].message}
        </span>
      {/if}

      {#if isCurrent || isPast}
        <div class="counters">
          {#each counters as c (c.label)}
            <div class="counter" aria-label={`${c.count} catégories ${c.label}`}>
              <span class="row tight"><Icon name={c.icon} size={14} color={c.color} /><span class="amount">{c.count}</span></span>
              <span class="caption truncate">{c.label}</span>
            </div>
          {/each}
        </div>
      {/if}

      {#if isCurrent}
        <div class="line projection">
          <div class="col tight">
            <span class="caption">Fin de mois estimée</span>
            <span class="amount">{budgetEuros(projected)}</span>
          </div>
          <span class="caption right" style:color={diff >= 0 ? "var(--positive)" : "var(--negative)"}>
            {diff >= 0 ? `${budgetEuros(diff)} sous le disponible` : `${budgetEuros(-diff)} au-dessus du disponible`}
          </span>
        </div>
      {/if}

      {#if isPast}
        <span class="pace row tight" style:color={totals.remaining >= 0 ? "var(--positive)" : "var(--negative)"}>
          <Icon name={totals.remaining >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"} size={15}
                color={totals.remaining >= 0 ? "var(--positive)" : "var(--negative)"} />
          {totals.remaining >= 0 ? `Économisé : ${budgetEuros(totals.remaining)}` : `Dépassé de ${budgetEuros(-totals.remaining)}`}
        </span>
      {/if}
    </div>
  {/if}
</Card>

<style>
  .content { gap: calc(var(--spacing) * 1.5); }
  .top { display: flex; align-items: center; gap: calc(var(--spacing) * 1.5); }
  .gauge-svg { flex-shrink: 0; overflow: visible; }
  .gauge-value { font-size: var(--body); font-weight: var(--amount-weight); fill: var(--text-primary); }
  .gauge-caption { font-size: var(--caption); fill: var(--text-secondary); }
  .figures { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; }
  .pace { font-weight: 600; }
  .counters { display: flex; gap: var(--spacing); }
  .counter {
    flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; gap: 2px;
    padding: calc(var(--spacing) * 0.6) 0; background: var(--surface-secondary); border-radius: var(--radius-small);
  }
  .projection { align-items: center; }
  .right { text-align: right; }
</style>
