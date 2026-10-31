<script lang="ts">
  // Carte « Suggestions » : budgets proposés d'après les derniers mois (BudgetSuggestionsCard de BudgetEnvelopesCard.swift).
  import { store } from "../../lib/app.svelte";
  import { budgetEuros } from "../../lib/logic/budgets";
  import { applySuggestion, budgetSuggestions, suggestionReasonLabel } from "../../lib/logic/planning";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";

  const suggestions = $derived(budgetSuggestions(store));

  function applyAll() {
    for (const s of suggestions) applySuggestion(store, s);
  }
</script>

{#if suggestions.length > 0}
  <Card>
    <div class="line center">
      <span class="title">Suggestions</span>
      {#if suggestions.length > 1}
        <button type="button" class="link caption" onclick={applyAll}>Tout appliquer</button>
      {/if}
    </div>
    {#each suggestions as suggestion (suggestion.id)}
      <div class="item">
        <CategoryBadge icon={suggestion.category.icon} colorIndex={suggestion.category.colorIndex} />
        <div class="body">
          <span class="truncate">{suggestion.category.label}</span>
          <span class="caption">{suggestionReasonLabel[suggestion.reason]}</span>
          <span class="caption">Moyenne sur {suggestion.monthsAnalysed} mois : {budgetEuros(suggestion.averageCents)}</span>
          <span class="caption nums primary">
            {suggestion.currentCents !== null
              ? `${budgetEuros(suggestion.currentCents)} → ${budgetEuros(suggestion.suggestedCents)}`
              : `Budget suggéré : ${budgetEuros(suggestion.suggestedCents)}`}
          </span>
        </div>
        <button type="button" class="btn small" aria-label={`Appliquer la suggestion pour ${suggestion.category.label}`}
                onclick={() => applySuggestion(store, suggestion)}>Appliquer</button>
      </div>
    {/each}
  </Card>
{/if}

<style>
  .center { align-items: center; }
  .link { border: none; background: transparent; padding: 0; color: var(--accent); }
  .item { display: flex; align-items: flex-start; gap: var(--spacing); }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .primary { color: var(--text-primary); }
</style>
