<script lang="ts">
  // Plan du mois, version minimaliste : une soustraction simple (revenus − fixes − courantes − épargne = libre) (BudgetPlanCard.swift).
  import { store } from "../../lib/app.svelte";
  import { budgetEuros, budgetStatuses } from "../../lib/logic/budgets";
  import { incomeSourceLabel, monthPlan } from "../../lib/logic/planning";
  import BudgetPlanEditor from "./BudgetPlanEditor.svelte";

  let { month }: { month: Date } = $props();

  let showEditor = $state(false);

  const plan = $derived(monthPlan(store, month));
  const statuses = $derived(budgetStatuses(store, month));
  const fixedCents = $derived(statuses.filter(x => x.isFixed).reduce((n, x) => n + x.budget, 0));
  const flexibleCents = $derived(statuses.filter(x => !x.isFixed).reduce((n, x) => n + x.budget, 0));
  const rest = $derived(plan.unallocatedCents);
  const hasIncome = $derived(plan.incomeSource !== "none");
</script>

{#snippet line(sign: string, title: string, cents: number)}
  <div class="line"><span>{sign} {title}</span><span class="nums">{budgetEuros(cents)}</span></div>
{/snippet}

<div class="col body">
  {#if hasIncome}
    <div class="col tight">
      <div class="line"><span>Revenus prévus</span><span class="nums">{budgetEuros(plan.expectedIncomeCents)}</span></div>
      {#if fixedCents > 0}{@render line("−", "Charges fixes", fixedCents)}{/if}
      {#if flexibleCents > 0}{@render line("−", "Dépenses courantes", flexibleCents)}{/if}
      {#if plan.savingsGoalCents > 0}{@render line("−", "Épargne visée", plan.savingsGoalCents)}{/if}
      <hr class="separator" />
      <div class="line strong" style:color={rest < 0 ? "var(--negative)" : undefined}>
        <span>{rest < 0 ? "= Manque" : "= Libre"}</span>
        <span class="nums">{budgetEuros(Math.abs(rest))}</span>
      </div>
    </div>
    <span class="caption">
      {incomeSourceLabel[plan.incomeSource]}
      <button type="button" class="link" aria-label="Modifier l'objectif d'épargne et les revenus prévus" onclick={() => (showEditor = true)}>Modifier</button>
    </span>
  {:else}
    <span class="secondary">Indique tes revenus prévus pour voir ce qu'il reste à répartir.</span>
    <button type="button" class="btn primary prompt" onclick={() => (showEditor = true)}>Prévoir mes revenus et mon épargne</button>
  {/if}
</div>

{#if showEditor}<BudgetPlanEditor onclose={() => (showEditor = false)} />{/if}

<style>
  .body { margin-top: var(--spacing); }
  .nums { font-variant-numeric: tabular-nums; }
  .strong { font-weight: 700; }
  .link { border: none; background: transparent; padding: 0 0 0 6px; font: inherit; color: var(--accent); }
  .prompt { align-self: flex-start; }
</style>
