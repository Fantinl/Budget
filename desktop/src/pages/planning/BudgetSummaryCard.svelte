<script lang="ts">
  // Résumé du mois : « Il te reste X € à dépenser », jauge et rythme par jour (BudgetSummaryCard.swift).
  import { store } from "../../lib/app.svelte";
  import { startOfMonth } from "../../lib/dates";
  import { budgetEuros, budgetStatuses, daysRemaining, isCurrentMonth, totalsOf } from "../../lib/logic/budgets";
  import Card from "../../ui/Card.svelte";
  import AddBudgetMenu from "./AddBudgetMenu.svelte";
  import EnvelopeEditorSheet from "./EnvelopeEditorSheet.svelte";

  let { month }: { month: Date } = $props();

  let editing = $state<string | null>(null);

  const isCurrent = $derived(isCurrentMonth(month));
  const isPast = $derived(startOfMonth(month).getTime() < startOfMonth(new Date()).getTime());
  const statuses = $derived(budgetStatuses(store, month));
  const totals = $derived(totalsOf(statuses));
  const remaining = $derived(totals.remaining);
  const days = $derived(daysRemaining(month));
  // Rythme par jour : sur le reste des enveloppes non fixes seulement (les charges fixes tombent à date fixe).
  const flexibleRemaining = $derived(statuses.filter(x => !x.isFixed).reduce((n, x) => n + x.budget - x.spent, 0));
  const perDay = $derived(isCurrent && flexibleRemaining > 0 && days > 0 ? Math.round(flexibleRemaining / days / 100) * 100 : null);
  const tint = $derived(totals.ratio > 1 ? "var(--negative)" : totals.ratio >= 0.8 ? "var(--warning)" : "var(--accent)");
  const caption = $derived(
    perDay !== null ? `≈ ${budgetEuros(perDay)} par jour pendant ${days} jour${days > 1 ? "s" : ""}`
      : isPast ? "Mois terminé" : !isCurrent ? "Mois à venir" : "");
</script>

<Card>
  {#if statuses.length === 0}
    <div class="col">
      <span class="secondary">Aucun budget n’est fixé ce mois-ci. Fixe un budget par catégorie, ou applique les suggestions pour démarrer à partir de tes dépenses habituelles.</span>
      <AddBudgetMenu {month} onpick={id => (editing = id)} />
    </div>
  {:else}
    <div class="col">
      <span class="headline" style:color={remaining < 0 ? "var(--negative)" : undefined}>
        {remaining >= 0 ? `Il te reste ${budgetEuros(remaining)} à dépenser` : `Budget dépassé de ${budgetEuros(-remaining)}`}
      </span>
      <div class="gauge" role="img"
           aria-label={`${budgetEuros(totals.spent)} dépensés sur ${budgetEuros(totals.budget)}`}>
        <div style:width="{Math.min(Math.max(totals.ratio, 0), 1) * 100}%" style:background={tint}></div>
      </div>
      <div class="col tight">
        <span class="caption">Dépensé {budgetEuros(totals.spent)} sur {budgetEuros(totals.budget)}</span>
        {#if caption}<span class="caption">{caption}</span>{/if}
      </div>
    </div>
  {/if}
</Card>

{#if editing}<EnvelopeEditorSheet categoryID={editing} {month} onclose={() => (editing = null)} />{/if}

<style>
  .headline { font-size: 22px; font-weight: 700; }
</style>
