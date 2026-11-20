<script lang="ts">
  // Page Budget « l'essentiel d'abord » : résumé, enveloppes, plan du mois, puis bilan de l'année et suggestions repliables (BudgetPlanningView.swift).
  import { store } from "../../lib/app.svelte";
  import { startOfMonth } from "../../lib/dates";
  import { budgetEuros, isCurrentMonth } from "../../lib/logic/budgets";
  import { annualBudgetBalance, budgetSuggestions, monthPlan } from "../../lib/logic/planning";
  import { monthStartsWithData } from "../../lib/logic/stats";
  import { pref } from "../../lib/prefs.svelte";
  import MonthPicker from "../../ui/MonthPicker.svelte";
  import BudgetSummaryCard from "./BudgetSummaryCard.svelte";
  import BudgetEnvelopesCard from "./BudgetEnvelopesCard.svelte";
  import BudgetSuggestionsCard from "./BudgetSuggestionsCard.svelte";
  import MonthPlanCard from "./MonthPlanCard.svelte";
  import AnnualBalanceCard from "./AnnualBalanceCard.svelte";
  import CollapsibleSection from "./CollapsibleSection.svelte";

  const showPlan = pref("budget.showPlan", false);
  const showYear = pref("budget.showYear", false);
  const showSuggestions = pref("budget.showSuggestions", false);

  let month = $state(startOfMonth(new Date()));
  const monthsWithData = $derived(monthStartsWithData(store.transactions));
  const isCurrent = $derived(isCurrentMonth(month));

  const plan = $derived(monthPlan(store, month));
  const planSummary = $derived(plan.incomeSource === "none" ? ""
    : plan.unallocatedCents < 0 ? `manque ${budgetEuros(-plan.unallocatedCents)}` : `${budgetEuros(plan.unallocatedCents)} libres`);

  const yearBalance = $derived(annualBudgetBalance(store, month).total.balance);
  const yearSummary = $derived(yearBalance > 0 ? `+${budgetEuros(yearBalance)} d’avance`
    : yearBalance < 0 ? `−${budgetEuros(-yearBalance)} de retard` : "");

  const suggestionCount = $derived(budgetSuggestions(store).length);
</script>

<div class="page" style:max-width="820px">
  <MonthPicker bind:month {monthsWithData} />
  <BudgetSummaryCard {month} />
  <BudgetEnvelopesCard {month} />
  <CollapsibleSection title="Plan du mois" open={showPlan} summary={planSummary}
                      summaryColor={plan.unallocatedCents < 0 ? "var(--negative)" : undefined}>
    <MonthPlanCard {month} />
  </CollapsibleSection>
  <CollapsibleSection title="Bilan de l’année" open={showYear} summary={yearSummary}
                      summaryColor={yearBalance < 0 ? "var(--negative)" : undefined}>
    <AnnualBalanceCard year={month} />
  </CollapsibleSection>
  {#if isCurrent && suggestionCount > 0}
    <CollapsibleSection title={`Suggestions (${suggestionCount})`} open={showSuggestions}>
      <BudgetSuggestionsCard />
    </CollapsibleSection>
  {/if}
</div>
