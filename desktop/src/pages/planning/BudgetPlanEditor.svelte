<script lang="ts">
  // Édition de l'objectif d'épargne et des revenus prévus (BudgetPlanEditor de BudgetPlanCard.swift).
  import { store } from "../../lib/app.svelte";
  import { amountInput, parseAmount } from "../../lib/format";
  import { setBudgetPlan } from "../../lib/logic/budgets";
  import Sheet from "../../ui/Sheet.svelte";

  let { onclose }: { onclose: () => void } = $props();

  const plan = store.budgetPlan;
  let savingsText = $state(plan.savingsGoalCents !== null ? amountInput(plan.savingsGoalCents) : "");
  let incomeText = $state(plan.expectedIncomeCents !== null ? amountInput(plan.expectedIncomeCents) : "");
  let autoIncome = $state(plan.expectedIncomeCents === null);

  /// Montant saisi (virgule acceptée) : null si vide ou invalide, doit être > 0.
  function parse(raw: string): number | null {
    const cents = parseAmount(raw.trim());
    return cents !== null && cents > 0 ? cents : null;
  }
  const isBlank = (raw: string) => raw.trim() === "";
  const savingsValid = $derived(isBlank(savingsText) || parse(savingsText) !== null);
  const canSave = $derived(savingsValid && (autoIncome || parse(incomeText) !== null));

  function save() {
    if (!canSave) return;
    setBudgetPlan(store, { savingsGoalCents: parse(savingsText), expectedIncomeCents: autoIncome ? null : parse(incomeText) });
    onclose();
  }
</script>

<Sheet title="Plan du mois" {onclose} width={420}>
  <label class="col tight">
    <span class="secondary">Objectif d'épargne mensuel</span>
    <input class="field" class:invalid={!savingsValid} inputmode="decimal" placeholder="Objectif d'épargne mensuel" bind:value={savingsText}
           aria-label="Objectif d'épargne mensuel en euros" />
    <span class="caption" class:negative={!savingsValid}>
      {savingsValid ? "Laisse vide pour ne pas viser d'épargne." : "Saisis un montant supérieur à 0."}
    </span>
  </label>

  <div class="col tight">
    <span class="title">Revenus prévus</span>
    <label class="row"><input type="checkbox" class="switch" bind:checked={autoIncome} /><span>Estimer automatiquement</span></label>
    {#if !autoIncome}
      <input class="field" class:invalid={!isBlank(incomeText) && parse(incomeText) === null} inputmode="decimal"
             placeholder="Revenus prévus par mois" bind:value={incomeText} aria-label="Revenus prévus par mois en euros" />
    {/if}
    {#if autoIncome}
      <span class="caption">Calculés d'après tes revenus récurrents, sinon la moyenne des 3 derniers mois.</span>
    {:else if !isBlank(incomeText) && parse(incomeText) === null}
      <span class="caption negative">Saisis un montant supérieur à 0.</span>
    {/if}
  </div>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>
