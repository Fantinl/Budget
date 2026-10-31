<script lang="ts">
  // Ligne de budget : pastille, nom, barre de progression, « dépensé / budget » (BudgetProgressRow.swift).
  // `detailed` = version des Statistiques : reste à dépenser et moyenne par jour.
  import CategoryBadge from "./CategoryBadge.svelte";
  import { type BudgetStatus, budgetEuros, daysRemaining } from "../lib/logic/budgets";
  import { categoryColor } from "../lib/theme.svelte";

  let { status, month = new Date(), detailed = false }: { status: BudgetStatus; month?: Date; detailed?: boolean } = $props();

  const barColor = $derived(
    status.state === "ok" ? categoryColor(status.category.colorIndex) : status.state === "warning" ? "var(--warning)" : "var(--negative)");
  const exceeded = $derived(status.state === "exceeded");
  const detailText = $derived.by(() => {
    let text = `Reste ${budgetEuros(status.remaining)}`;
    const days = daysRemaining(month);
    if (days > 0) text += ` · ${budgetEuros(status.remaining / days)} / jour possible`;
    return text;
  });
</script>

<div class="row">
  <CategoryBadge icon={status.category.icon} colorIndex={status.category.colorIndex} />
  <div class="body">
    <div class="head">
      <span class="label truncate" class:negative={exceeded}>{status.category.label}</span>
      <span class="caption nums truncate" class:negative={exceeded}>{budgetEuros(status.spent)} / {budgetEuros(status.budget)}</span>
    </div>
    <div class="bar"><div style:width="{Math.min(1, Math.max(0, status.ratio)) * 100}%" style:background={barColor}></div></div>
    {#if exceeded}
      <span class="caption negative">Dépassé de {budgetEuros(status.overspent)}</span>
    {:else if detailed}
      <span class="caption">{detailText}</span>
    {/if}
  </div>
</div>

<style>
  .row { display: flex; align-items: flex-start; gap: var(--spacing); }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
  .head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--spacing); }
  .label { color: var(--text-primary); }
  .bar { height: 5px; border-radius: calc(var(--radius-small) / 2); background: var(--surface-secondary); overflow: hidden; }
  .bar > div { height: 100%; border-radius: calc(var(--radius-small) / 2); }
</style>
