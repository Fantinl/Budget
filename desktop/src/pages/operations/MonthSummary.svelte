<script lang="ts">
  // Résumé du mois : carte « Solde du mois » (dépenses, revenus, répartition, fin de mois prévue).
  // Port de MonthSummaryView.swift.
  import { type Transaction, isEarning, isSpending } from "../../lib/model";
  import { store } from "../../lib/app.svelte";
  import { euros } from "../../lib/format";
  import { isInMonth, startOfMonth } from "../../lib/dates";
  import { monthForecast } from "../../lib/logic/forecast";
  import { categoryColor, currentTheme } from "../../lib/theme.svelte";
  import Card from "../../ui/Card.svelte";
  import BudgetsCard from "../../ui/BudgetsCard.svelte";

  let { transactions, month = null }: {
    transactions: Transaction[];
    /// Mois affiché ; par défaut déduit des opérations (sinon le mois en cours).
    month?: Date | null;
  } = $props();

  const displayed = $derived(startOfMonth(month ?? transactions[0]?.date ?? new Date()));
  const isCurrentMonth = $derived(isInMonth(displayed, new Date()));
  const expenses = $derived(transactions.filter(isSpending).reduce((s, t) => s + t.amountCents, 0));
  const income = $derived(transactions.filter(isEarning).reduce((s, t) => s + t.amountCents, 0));
  const balance = $derived(income - expenses);

  /// Total des dépenses par catégorie, de la plus grosse à la plus petite.
  const byCategory = $derived.by(() => {
    const totals = new Map<string, number>();
    for (const t of transactions) if (isSpending(t)) totals.set(t.categoryID, (totals.get(t.categoryID) ?? 0) + t.amountCents);
    return [...totals].map(([id, total]) => ({ category: store.category(id), total })).sort((a, b) => b.total - a.total);
  });

  const projected = $derived(isCurrentMonth ? monthForecast(store).projectedCents : 0);
  const tinted = $derived(currentTheme().heroTintsBalance);
</script>

<div class="summary">
  <Card hero>
    <span class="caption" style:color="var(--hero-text-secondary)">Solde du mois</span>
    <span class="large-amount balance" style:color={tinted ? (balance >= 0 ? "var(--positive)" : "var(--negative)") : "var(--hero-text-primary)"}>{euros(balance)}</span>

    <div class="stats">
      <span class="caption stat"><span style:color="var(--hero-text-secondary)">Dépenses</span> <span class="nums" style:color="var(--hero-text-primary)">{euros(expenses)}</span></span>
      <span class="caption stat"><span style:color="var(--hero-text-secondary)">Revenus</span> <span class="nums" style:color="var(--hero-text-primary)">{euros(income)}</span></span>
    </div>

    {#if byCategory.length > 0}
      <div class="bar">
        {#each byCategory as item (item.category.id)}
          <span style:background={categoryColor(item.category.colorIndex)} style:flex="{item.total} 1 0"></span>
        {/each}
      </div>
    {/if}

    {#if isCurrentMonth}
      <span class="caption stat">
        <span style:color="var(--hero-text-secondary)">Fin de mois prévue</span>
        <span class="nums" style:color="var(--hero-text-primary)">{(projected > 0 ? "+" : "") + euros(projected)}</span>
      </span>
    {/if}
  </Card>
  <BudgetsCard month={displayed} limit={4} />
</div>

<style>
  .summary { display: flex; flex-direction: column; gap: var(--padding); }
  .balance { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .stats { display: flex; flex-wrap: wrap; gap: var(--padding); }
  .stat { display: inline-flex; gap: 6px; white-space: nowrap; }
  .bar { display: flex; gap: 2px; height: 6px; border-radius: calc(var(--radius-small) / 2); overflow: hidden; background: var(--surface-secondary); }
  .bar span { min-width: 2px; }
</style>
