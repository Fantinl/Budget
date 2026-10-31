<script lang="ts">
  // Carte « Budgets » : toutes les catégories budgétées, repliable au-delà de `limit` (BudgetsCard de BudgetProgressRow.swift).
  import { store } from "../lib/app.svelte";
  import { budgetEuros, budgetStatuses, totalsOf } from "../lib/logic/budgets";
  import Card from "./Card.svelte";
  import BudgetProgressRow from "./BudgetProgressRow.svelte";

  let { month, limit, detailed = false }: {
    month: Date;
    /// Nombre de lignes visibles avant « Voir tout » (undefined = toutes).
    limit?: number;
    detailed?: boolean;
  } = $props();

  let expanded = $state(false);

  const statuses = $derived(budgetStatuses(store, month));
  const totals = $derived(totalsOf(statuses));
  const visible = $derived(limit !== undefined && !expanded ? statuses.slice(0, limit) : statuses);
</script>

{#if statuses.length > 0}
  <Card>
    <span class="title">Budgets</span>
    {#if detailed}
      <span class="caption">Total : {budgetEuros(totals.spent)} / {budgetEuros(totals.budget)}</span>
    {/if}
    {#each visible as status (status.id)}
      <BudgetProgressRow {status} {month} {detailed} />
    {/each}
    {#if limit !== undefined && statuses.length > limit}
      <button type="button" class="link" onclick={() => (expanded = !expanded)}>{expanded ? "Réduire" : "Voir tout"}</button>
    {/if}
  </Card>
{/if}

<style>
  .link { align-self: flex-start; border: none; background: transparent; padding: 0; color: var(--accent); font-size: var(--caption); }
</style>
