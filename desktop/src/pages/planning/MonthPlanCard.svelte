<script lang="ts">
  // Plan du mois : revenus − charges fixes − enveloppes − épargne = reste à répartir, puis le réalisé (BudgetPlanCard.swift).
  import { store } from "../../lib/app.svelte";
  import { shortDate } from "../../lib/format";
  import { budgetEuros } from "../../lib/logic/budgets";
  import { incomeSourceLabel, monthPlan } from "../../lib/logic/planning";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import BudgetPlanEditor from "./BudgetPlanEditor.svelte";

  let { month }: { month: Date } = $props();

  let showFixed = $state(false);
  let showEditor = $state(false);

  const plan = $derived(monthPlan(store, month));
  const rest = $derived(plan.unallocatedCents);
  const isEmpty = $derived(plan.incomeSource === "none" && plan.savingsGoalCents === 0 && plan.envelopesCents === 0 && plan.fixedCharges.length === 0);

  // Barre empilée ; si le plan dépasse les revenus, la barre est répartie sur le total du plan.
  const parts = $derived([
    { label: "Charges fixes", cents: plan.fixedTotalCents, color: "var(--text-tertiary)" },
    { label: "Enveloppes", cents: plan.envelopesCents, color: "var(--accent)" },
    { label: "Épargne", cents: plan.savingsGoalCents, color: "var(--positive)" },
    { label: "Reste", cents: Math.max(0, rest), color: "var(--surface-secondary)" },
  ]);
  const barTotal = $derived(Math.max(plan.expectedIncomeCents, parts.reduce((n, p) => n + p.cents, 0)));
  const savingsProgress = $derived(plan.savingsGoalCents > 0
    ? Math.min(Math.max(plan.actualSavingsCents / plan.savingsGoalCents, 0), 1) : 0);
</script>

{#snippet line(title: string, cents: number, sign: string, tint: string, detail?: string)}
  <div class="line first">
    <div class="col tight">
      <span>{title}</span>
      {#if detail}<span class="caption">{detail}</span>{/if}
    </div>
    <span class="amount" style:color={tint}>{sign}{sign ? " " : ""}{budgetEuros(cents)}</span>
  </div>
{/snippet}

{#snippet row(title: string, value: string, tint?: string)}
  <div class="line">
    <span class="secondary">{title}</span>
    <span class="medium" style:color={tint}>{value}</span>
  </div>
{/snippet}

<Card>
  <div class="col wide">
    <div class="line center">
      <span class="title">Plan du mois</span>
      <button type="button" class="link strong" aria-label="Modifier l'objectif d'épargne et les revenus prévus" onclick={() => (showEditor = true)}>Modifier</button>
    </div>

    {#if isEmpty}
      <div class="col">
        <span class="secondary">Renseigne tes revenus prévus et, si tu veux, un objectif d'épargne : tu verras ce qu'il te reste à répartir chaque mois.</span>
        <button type="button" class="btn primary prompt" onclick={() => (showEditor = true)}>Renseigner mes revenus</button>
      </div>
    {:else}
      <div class="col cascade">
        {@render line("Revenus prévus", plan.expectedIncomeCents, "", "var(--positive)", incomeSourceLabel[plan.incomeSource])}
        {#if plan.fixedCharges.length === 0}
          {@render line("Charges fixes", plan.fixedTotalCents, "−", "var(--text-primary)")}
        {:else}
          <button type="button" class="toggle" aria-expanded={showFixed} onclick={() => (showFixed = !showFixed)}>
            <span class="chevron" class:open={showFixed}><Icon name="chevron.right" size={12} color="var(--text-tertiary)" /></span>
            <div class="grow">{@render line("Charges fixes", plan.fixedTotalCents, "−", "var(--text-primary)")}</div>
          </button>
          {#if showFixed}
            <div class="col tight details">
              {#each plan.fixedCharges as charge (charge.id)}
                <div class="detail caption">
                  <span class="truncate grow">{charge.name}</span>
                  <span class="tertiary">{shortDate(charge.date)}</span>
                  <span class="amount-col">{budgetEuros(charge.amountCents)}</span>
                </div>
              {/each}
            </div>
          {/if}
        {/if}
        {@render line("Enveloppes", plan.envelopesCents, "−", "var(--text-primary)", "Budgets des catégories")}
        {@render line("Épargne visée", plan.savingsGoalCents, "−", "var(--text-primary)")}
        <hr class="separator" />
        <div class="col tight">
          <div class="line">
            <span class="strong">Reste à répartir</span>
            <span class="amount" style:color={rest >= 0 ? "var(--positive)" : "var(--negative)"}>{budgetEuros(rest)}</span>
          </div>
          <span class="caption" style:color={rest >= 0 ? undefined : "var(--negative)"}>
            {rest >= 0 ? "à répartir dans tes enveloppes ou ton épargne" : `ton plan dépasse tes revenus de ${budgetEuros(-rest)}`}
          </span>
        </div>
      </div>

      {#if plan.expectedIncomeCents > 0}
        <div class="col tight">
          <div class="stack">
            {#each parts as p (p.label)}
              {#if barTotal > 0 && p.cents / barTotal > 0}
                <div style:width="calc((100% - 6px) * {p.cents / barTotal})" style:background={p.color}></div>
              {/if}
            {/each}
          </div>
          <div class="legend">
            {#each parts as p (p.label)}
              {#if p.cents > 0}
                <span class="caption row tight"><i style:background={p.color}></i>{p.label}</span>
              {/if}
            {/each}
          </div>
        </div>
      {/if}

      <hr class="separator" />
      <div class="col cascade">
        <span class="strong">Réalisé</span>
        {@render row("Revenus reçus", `${budgetEuros(plan.actualIncomeCents)} / ${budgetEuros(plan.expectedIncomeCents)}`)}
        {@render row("Dépensé", budgetEuros(plan.actualSpentCents))}
        {@render row("Épargne réelle", budgetEuros(plan.actualSavingsCents), plan.actualSavingsCents >= 0 ? "var(--positive)" : "var(--negative)")}
        {#if plan.savingsGoalCents > 0}
          <div class="col tight">
            <div class="gauge"><div style:width="{savingsProgress * 100}%"
                 style:background={plan.actualSavingsCents >= plan.savingsGoalCents ? "var(--positive)" : "var(--accent)"}></div></div>
            <span class="caption">{Math.round(savingsProgress * 100)} % de ton objectif de {budgetEuros(plan.savingsGoalCents)}</span>
          </div>
        {/if}
        {#if plan.unbudgetedSpentCents > 0}
          {@render row("Dépenses hors budget", budgetEuros(plan.unbudgetedSpentCents))}
        {/if}
      </div>
    {/if}
  </div>
</Card>

{#if showEditor}<BudgetPlanEditor onclose={() => (showEditor = false)} />{/if}

<style>
  .wide { gap: calc(var(--spacing) * 1.25); }
  .cascade { gap: calc(var(--spacing) * 0.75); }
  .center { align-items: center; }
  .first { align-items: first baseline; }
  .strong { font-weight: 600; }
  .medium { font-weight: 500; }
  .link { border: none; background: transparent; padding: 0; color: var(--accent); }
  .prompt { align-self: flex-start; }
  .toggle { display: flex; align-items: center; gap: 6px; width: 100%; border: none; background: transparent; padding: 0; color: inherit; text-align: left; }
  .grow { flex: 1; min-width: 0; }
  .chevron { display: inline-flex; transition: transform 0.15s; }
  .chevron.open { transform: rotate(90deg); }
  .details { padding-left: 20px; }
  .detail { display: flex; align-items: baseline; gap: var(--spacing); }
  .amount-col { min-width: 70px; text-align: right; }
  .stack { display: flex; gap: 2px; height: 12px; border-radius: var(--radius-small); overflow: hidden; }
  .stack > div { min-width: 2px; border-radius: 3px; flex: 0 0 auto; }
  .legend { display: flex; flex-wrap: wrap; gap: var(--spacing); }
  .legend i { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
</style>
