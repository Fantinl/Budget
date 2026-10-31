<script lang="ts">
  // Carte « Enveloppes » : budgets par catégorie du mois, avec rythme, projection et report (BudgetEnvelopesCard.swift).
  import { store } from "../../lib/app.svelte";
  import { budgetEuros, budgetStatuses, daysRemaining, elapsedFraction, hasBudgetOverride, isCurrentMonth } from "../../lib/logic/budgets";
  import { projectedSpending } from "../../lib/logic/planning";
  import { categoryColor } from "../../lib/theme.svelte";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Icon from "../../ui/Icon.svelte";
  import EnvelopeEditorSheet from "./EnvelopeEditorSheet.svelte";

  let { month }: { month: Date } = $props();

  let editing = $state<string | null>(null);
  let menuOpen = $state(false);
  let menu: HTMLElement | undefined = $state();

  const isCurrent = $derived(isCurrentMonth(month));
  const statuses = $derived(budgetStatuses(store, month));
  const elapsed = $derived(elapsedFraction(month));
  const days = $derived(daysRemaining(month));
  /// Catégories de dépense visibles qui n'ont pas de budget ce mois-ci.
  const others = $derived.by(() => {
    const budgeted = new Set(statuses.map(s => s.id));
    return store.categories.filter(c => c.kind === "expense" && !c.isHidden && !budgeted.has(c.id));
  });
  const spent = $derived(statuses.reduce((n, s) => n + s.spent, 0));
  const available = $derived(statuses.reduce((n, s) => n + s.budget, 0));
  /// Projection de chaque enveloppe (mois en cours seulement).
  const projections = $derived(new Map(statuses.map(s => [s.id, isCurrent ? projectedSpending(store, s.category, month) : null])));

  const barColor = (state: string, colorIndex: number) =>
    state === "ok" ? categoryColor(colorIndex) : state === "warning" ? "var(--warning)" : "var(--negative)";

  function onwindowdown(e: MouseEvent) {
    if (menuOpen && menu && !menu.contains(e.target as Node)) menuOpen = false;
  }
</script>

<svelte:window onmousedown={onwindowdown} />

<Card>
  <span class="title">Enveloppes</span>
  {#if statuses.length === 0}
    <span class="caption">Aucun budget ce mois-ci. Fixe une enveloppe par catégorie pour suivre tes dépenses.</span>
  {:else}
    {#each statuses as status (status.id)}
      {@const projected = projections.get(status.id) ?? null}
      {@const exceeded = status.state === "exceeded"}
      <button type="button" class="envelope" aria-label={`${status.category.label} : modifier le budget`} onclick={() => (editing = status.id)}>
        <CategoryBadge icon={status.category.icon} colorIndex={status.category.colorIndex} />
        <div class="body">
          <div class="head">
            <span class="truncate" class:negative={exceeded}>{status.category.label}</span>
            <span class="caption nums truncate" class:negative={exceeded}>{budgetEuros(status.spent)} / {budgetEuros(status.budget)}</span>
          </div>
          <div class="gauge-box">
            <div class="track"></div>
            <div class="fill" style:width="{Math.min(1, Math.max(0, status.ratio)) * 100}%" style:background={barColor(status.state, status.category.colorIndex)}></div>
            {#if isCurrent}
              <div class="marker" style:left="clamp(0px, calc({Math.min(1, Math.max(0, elapsed))} * 100% - 1px), calc(100% - 2px))"></div>
            {/if}
          </div>
          {#if exceeded}
            <span class="caption negative">Dépassé de {budgetEuros(status.overspent)}</span>
          {:else}
            <span class="caption">
              Reste {budgetEuros(status.remaining)}{#if isCurrent && days > 0} · {budgetEuros(status.remaining / days)} / jour possible{/if}
            </span>
          {/if}
          {#if projected !== null}
            <span class="caption" style:color={projected > status.budget && !exceeded ? "var(--warning)" : undefined}>
              Fin de mois estimée : {budgetEuros(projected)}
            </span>
          {/if}
          {#if status.carryOver !== 0 || hasBudgetOverride(status.category, month)}
            <div class="chips">
              {#if status.carryOver !== 0}
                <span class="chip" style:--c={status.carryOver > 0 ? "var(--positive)" : "var(--negative)"}>
                  {status.carryOver > 0 ? "+" : "−"}{budgetEuros(Math.abs(status.carryOver))} reportés
                </span>
              {/if}
              {#if hasBudgetOverride(status.category, month)}
                <span class="chip" style:--c="var(--accent)">Budget de ce mois</span>
              {/if}
            </div>
          {/if}
        </div>
        <span class="chev"><Icon name="chevron.right" size={11} color="var(--text-tertiary)" /></span>
      </button>
    {/each}
  {/if}

  {#if others.length > 0}
    <div class="menu" bind:this={menu}>
      <button type="button" class="add caption" aria-expanded={menuOpen} onclick={() => (menuOpen = !menuOpen)}>
        <Icon name="plus.circle" size={14} color="var(--accent)" />Ajouter un budget
      </button>
      {#if menuOpen}
        <div class="menu-list" role="menu">
          {#each others as category (category.id)}
            <button type="button" role="menuitem" class="menu-item" onclick={() => { editing = category.id; menuOpen = false; }}>{category.label}</button>
          {/each}
        </div>
      {/if}
    </div>
  {/if}

  {#if statuses.length > 0}
    <hr class="separator" />
    <div class="line">
      <span class="caption">Total</span>
      <span class="caption nums" style:color={spent > available ? "var(--negative)" : "var(--text-primary)"}>{budgetEuros(spent)} / {budgetEuros(available)}</span>
    </div>
  {/if}
</Card>

{#if editing}<EnvelopeEditorSheet categoryID={editing} {month} onclose={() => (editing = null)} />{/if}

<style>
  .envelope {
    display: flex; align-items: flex-start; gap: var(--spacing); width: 100%; border: none; background: transparent;
    padding: 0; color: inherit; text-align: left; font: inherit;
  }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
  .head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--spacing); }
  .gauge-box { position: relative; height: 11px; }
  .track, .fill {
    position: absolute; left: 0; top: 3px; height: 5px; border-radius: calc(var(--radius-small) / 2);
  }
  .track { width: 100%; background: var(--surface-secondary); }
  .marker { position: absolute; top: 0; width: 2px; height: 11px; border-radius: 1px; background: color-mix(in srgb, var(--text-primary) 70%, transparent); }
  .chips { display: flex; gap: 6px; flex-wrap: wrap; }
  .chip {
    font-size: var(--caption); padding: 2px 8px; border-radius: 999px; color: var(--c);
    background: color-mix(in srgb, var(--c) 14%, transparent);
  }
  .chev { padding-top: 4px; }
  .menu { position: relative; align-self: flex-start; }
  .add { display: inline-flex; align-items: center; gap: 6px; border: none; background: transparent; padding: 0; color: var(--accent); }
  .menu-list {
    position: absolute; top: calc(100% + 4px); left: 0; z-index: 30; min-width: 200px; max-height: 280px; overflow: auto;
    padding: 4px; display: flex; flex-direction: column; background: var(--surface); border-radius: var(--radius-small);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2), 0 0 0 1px var(--separator);
  }
  .menu-item { border: none; background: transparent; text-align: left; padding: 5px 10px; border-radius: 4px; color: var(--text-primary); }
  .menu-item:hover { background: var(--accent); color: var(--on-accent); }
</style>
