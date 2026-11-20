<script lang="ts">
  // Carte « Suggestions » : budgets proposés d'après les derniers mois (BudgetSuggestionsCard de BudgetEnvelopesCard.swift).
  import { store } from "../../lib/app.svelte";
  import { budgetEuros } from "../../lib/logic/budgets";
  import { applySuggestion, budgetSuggestions, suggestionReasonLabel } from "../../lib/logic/planning";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";

  const suggestions = $derived(budgetSuggestions(store));

  function applyAll() {
    for (const s of suggestions) applySuggestion(store, s);
  }
</script>

{#if suggestions.length > 0}
  <div class="inner">
    {#if suggestions.length > 1}
      <div class="line center end">
        <button type="button" class="link caption" onclick={applyAll}>Tout appliquer</button>
      </div>
    {/if}
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
  </div>
{/if}

<style>
  .inner { display: flex; flex-direction: column; gap: var(--spacing); }
  .end { justify-content: flex-end; }
  .center { align-items: center; }
  .link { border: none; background: transparent; padding: 0; color: var(--accent); }
  .item { display: flex; align-items: flex-start; gap: var(--spacing); }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .primary { color: var(--text-primary); }
</style>
