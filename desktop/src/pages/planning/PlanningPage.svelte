<script lang="ts">
  // Page Budget : enveloppes par catégorie, plan du mois et équilibre de l'année (BudgetPlanningView.swift).
  import { store } from "../../lib/app.svelte";
  import { startOfMonth } from "../../lib/dates";
  import { isCurrentMonth } from "../../lib/logic/budgets";
  import { monthStartsWithData } from "../../lib/logic/stats";
  import MonthPicker from "../../ui/MonthPicker.svelte";
  import BudgetSummaryCard from "./BudgetSummaryCard.svelte";
  import MonthPlanCard from "./MonthPlanCard.svelte";
  import BudgetEnvelopesCard from "./BudgetEnvelopesCard.svelte";
  import BudgetSuggestionsCard from "./BudgetSuggestionsCard.svelte";
  import AnnualBalanceCard from "./AnnualBalanceCard.svelte";

  let month = $state(startOfMonth(new Date()));
  const monthsWithData = $derived(monthStartsWithData(store.transactions));
  const isCurrent = $derived(isCurrentMonth(month));
</script>

<div class="page" style:max-width="820px">
  <MonthPicker bind:month {monthsWithData} />
  <BudgetSummaryCard {month} />
  <MonthPlanCard {month} />
  <BudgetEnvelopesCard {month} />
  {#if isCurrent}<BudgetSuggestionsCard />{/if}
  <AnnualBalanceCard year={month} />
</div>
