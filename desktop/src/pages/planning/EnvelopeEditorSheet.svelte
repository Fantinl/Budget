<script lang="ts">
  // Éditeur de budget : par défaut, propre au mois, report, retrait (EnvelopeEditorSheet de BudgetEnvelopesCard.swift).
  import { store } from "../../lib/app.svelte";
  import { amountInput } from "../../lib/format";
  import { monthTitle } from "../../lib/format";
  import { evaluate } from "../../lib/logic/amountExpression";
  import { plannedBudget, removeBudget, setBudgetOverride, setBudgetRollover, setMonthlyBudget } from "../../lib/logic/budgets";
  import { monthKey } from "../../lib/dates";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Sheet from "../../ui/Sheet.svelte";

  let { categoryID, month, onclose }: { categoryID: string; month: Date; onclose: () => void } = $props();

  const category = $derived(store.categories.find(c => c.id === categoryID) ?? null);

  // État initial lu une seule fois (comme `load()` en Swift)
  const initial = store.categories.find(c => c.id === categoryID) ?? null;
  // svelte-ignore state_referenced_locally
  const override = initial?.budgetOverridesCents?.[monthKey(month)];
  let defaultText = $state(initial?.monthlyBudgetCents && initial.monthlyBudgetCents > 0 ? amountInput(initial.monthlyBudgetCents) : "");
  let monthText = $state(override !== undefined ? amountInput(override) : "");
  let rollover = $state(initial?.budgetRollover === true);

  const isBlank = (text: string) => text.trim() === "";
  const defaultValue = $derived(isBlank(defaultText) ? null : evaluate(defaultText));
  const monthValue = $derived(isBlank(monthText) ? null : evaluate(monthText));
  const defaultIsValid = $derived(isBlank(defaultText) || (defaultValue !== null && defaultValue > 0));
  /// Le budget du mois peut valoir 0 (pas de budget ce mois-là).
  const monthIsValid = $derived(isBlank(monthText) || (monthValue !== null && monthValue >= 0));
  const hasAnyBudget = $derived(!isBlank(defaultText) || !isBlank(monthText));
  const canSave = $derived(defaultIsValid && monthIsValid && hasAnyBudget);
  const monthName = $derived(monthTitle(month).toLowerCase());
  const removable = $derived(category !== null && (plannedBudget(category, month) > 0 || category.monthlyBudgetCents !== null));

  function save() {
    if (!category || !canSave) return;
    setMonthlyBudget(store, defaultValue, category);
    setBudgetOverride(store, monthValue, category, month);
    if ((category.budgetRollover === true) !== rollover) setBudgetRollover(store, rollover, category);
    onclose();
  }

  function remove() {
    if (!category) return;
    removeBudget(store, category);
    onclose();
  }
</script>

<Sheet title="Budget" {onclose} width={440}>
  {#if category}
    <div class="row">
      <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={40} />
      <span class="title">{category.label}</span>
    </div>

    <label class="col tight">
      <span class="title">Tous les mois</span>
      <input class="field" class:invalid={!defaultIsValid} inputmode="decimal" placeholder="Budget par défaut (€ / mois)" bind:value={defaultText} />
      <span class="caption" class:negative={!defaultIsValid}>
        {defaultIsValid ? "Montant appliqué à chaque mois, sauf budget propre à un mois." : "Saisis un montant supérieur à 0."}
      </span>
    </label>

    <div class="col tight">
      <span class="title">Pour {monthName} seulement</span>
      <input class="field" class:invalid={!monthIsValid} inputmode="decimal" placeholder="Budget pour ce mois (facultatif)" bind:value={monthText} />
      {#if !isBlank(monthText)}
        <button type="button" class="link" onclick={() => (monthText = "")}>Revenir au budget par défaut</button>
      {/if}
      <span class="caption" class:negative={!monthIsValid}>
        {monthIsValid ? "Saisis 0 pour ne pas avoir de budget ce mois-là." : "Saisis un montant positif ou nul."}
      </span>
    </div>

    <div class="col tight">
      <label class="row"><input type="checkbox" class="switch" bind:checked={rollover} /><span>Reporter le reste sur le mois suivant</span></label>
      <span class="caption">Ce que tu n'as pas dépensé (ou ton dépassement) s'ajoute au budget du mois suivant. Remis à zéro en janvier.</span>
    </div>

    {#if removable}
      <button type="button" class="btn danger remove" onclick={remove}>Retirer le budget</button>
    {/if}
  {/if}

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .link { align-self: flex-start; border: none; background: transparent; padding: 0; color: var(--accent); }
  .remove { align-self: flex-start; }
</style>
