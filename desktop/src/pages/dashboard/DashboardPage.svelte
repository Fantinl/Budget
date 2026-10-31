<script lang="ts">
  // Page d'accueil : l'essentiel du budget en cartes cliquables (DashboardView.swift).
  import { navigate, store } from "../../lib/app.svelte";
  import type { Draft } from "../../lib/drafts";
  import { euros, shortDate } from "../../lib/format";
  import { makeDashboardSummary } from "../../lib/logic/dashboard";
  import { budgetEuros } from "../../lib/logic/budgets";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import BudgetProgressRow from "../../ui/BudgetProgressRow.svelte";
  import TransactionRow from "../../ui/TransactionRow.svelte";
  import OperationEditor from "../operations/OperationEditor.svelte";

  const summary = $derived(makeDashboardSummary(store));
  let draft = $state<Draft | null>(null);
</script>

{#snippet title(text: string)}<span class="caption">{text}</span>{/snippet}

{#snippet line(label: string, value: string, color?: string)}
  <div class="line">
    <span class="secondary">{label}</span>
    <span class="amount" style:color>{value}</span>
  </div>
{/snippet}

<div class="page">
  <Card hero onclick={() => navigate("accounts")}>
    <span class="caption" style:color="var(--hero-text-secondary)">Argent disponible</span>
    <span class="large-amount" style:color="var(--hero-text-primary)">{euros(summary.availableCents)}</span>
    {#if summary.currentAccounts.length > 1}
      <div class="col tight accounts">
        {#each summary.currentAccounts as item (item.account.id)}
          <div class="line caption" style:color="var(--hero-text-secondary)">
            <span>{item.account.name}</span>
            <span class="nums">{euros(item.balanceCents)}</span>
          </div>
        {/each}
      </div>
    {/if}
  </Card>

  <div class="grid">
    <Card onclick={() => navigate("stats")}>
      {@render title("Reste ce mois-ci")}
      <span class="large-amount" style:color={summary.monthRemainingCents >= 0 ? "var(--positive)" : "var(--negative)"}>
        {euros(summary.monthRemainingCents)}
      </span>
      {@render line("Revenus", euros(summary.monthIncomeCents), "var(--positive)")}
      {@render line("Dépenses", euros(summary.monthSpentCents))}
      {@render line("Fin de mois prévue", euros(summary.forecastCents), summary.forecastCents >= 0 ? "var(--text-primary)" : "var(--negative)")}
      {#if summary.budgetTotals}
        {@render line("Budgets restants", budgetEuros(summary.budgetTotals.remaining),
                      summary.budgetTotals.remaining >= 0 ? "var(--text-primary)" : "var(--negative)")}
      {/if}
    </Card>

    {#if summary.izly}
      <Card onclick={() => navigate("accounts")}>
        {@render title("Izly")}
        <span class="large-amount">{euros(summary.izly.balanceCents)}</span>
        <span class="secondary">≈ {summary.izly.meals} repas restants</span>
        {#if summary.izlyIsLow}
          <span class="caption warning row tight"><Icon name="exclamationmark.circle" size={13} color="var(--warning)" />Pense à recharger</span>
        {/if}
      </Card>
    {/if}

    <Card onclick={() => navigate("accounts")}>
      {@render title("Épargne et placements")}
      <span class="large-amount">{euros(summary.savingsCents)}</span>
    </Card>

    <Card onclick={() => navigate("accounts")}>
      {@render title("Patrimoine total")}
      <span class="large-amount">{euros(summary.wealthCents)}</span>
    </Card>

    {#if summary.topBudgets.length > 0}
      <Card onclick={() => navigate("planning")}>
        {@render title("Budgets")}
        {#each summary.topBudgets as status (status.id)}
          <BudgetProgressRow {status} />
        {/each}
      </Card>
    {/if}

    <Card onclick={() => navigate("accounts")}>
      {@render title("À venir")}
      {#if summary.upcoming.length === 0}
        <span class="secondary">Rien de prévu sous 30 jours.</span>
      {:else}
        {#each summary.upcoming as item (item.id)}
          <div class="upcoming">
            <span class="caption date">{shortDate(item.date)}</span>
            <span class="truncate name">{item.name}</span>
            <span class="amount" style:color={item.amountCents >= 0 ? "var(--positive)" : "var(--text-primary)"}>{euros(item.amountCents)}</span>
          </div>
        {/each}
      {/if}
    </Card>

    <Card>
      <button type="button" class="head" onclick={() => navigate("operations")}>
        {@render title("Dernières opérations")}
        <Icon name="chevron.right" size={12} color="var(--text-tertiary)" />
      </button>
      {#if summary.latest.length === 0}
        <span class="secondary">Aucune opération.</span>
      {/if}
      {#each summary.latest as t (t.id)}
        <button type="button" class="tx" onclick={() => (draft = { transaction: t, isNew: false })}>
          <TransactionRow transaction={t} />
        </button>
      {/each}
    </Card>
  </div>
</div>

{#if draft}<OperationEditor {draft} onclose={() => (draft = null)} />{/if}

<style>
  .accounts { margin-top: 0; }
  .upcoming { display: flex; align-items: baseline; gap: var(--spacing); }
  .upcoming .date { width: 56px; flex-shrink: 0; }
  .upcoming .name { flex: 1; }
  .head {
    display: flex; align-items: center; justify-content: space-between; border: none; background: transparent;
    padding: 0; width: 100%; color: inherit; text-align: left;
  }
  .tx { display: block; width: 100%; border: none; background: transparent; padding: 0; color: inherit; text-align: left; }
</style>
