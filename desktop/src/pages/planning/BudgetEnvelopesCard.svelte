<script lang="ts">
  // Section « Enveloppes » : une ligne par catégorie budgétée (reste ou dépassement), clic = éditeur (BudgetEnvelopesCard.swift).
  import { store } from "../../lib/app.svelte";
  import { budgetEuros, budgetStatuses, fixedOccurrences, isCurrentMonth } from "../../lib/logic/budgets";
  import { startOfDay } from "../../lib/dates";
  import { categoryColor } from "../../lib/theme.svelte";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import AddBudgetMenu from "./AddBudgetMenu.svelte";
  import EnvelopeEditorSheet from "./EnvelopeEditorSheet.svelte";

  let { month }: { month: Date } = $props();

  let editing = $state<string | null>(null);

  const statuses = $derived(budgetStatuses(store, month));
  const fixed = $derived(statuses.filter(x => x.isFixed));
  const regular = $derived(statuses.filter(x => !x.isFixed));
  const fixedSpent = $derived(fixed.reduce((n, x) => n + x.spent, 0));
  const fixedBudget = $derived(fixed.reduce((n, x) => n + x.budget, 0));
  const occurrencesByCategory = $derived(fixedOccurrences(store, month));

  /// Jour de la prochaine échéance (après aujourd'hui, mois en cours seulement), null sinon.
  function nextDay(id: string): number | null {
    if (!isCurrentMonth(month)) return null;
    const today = startOfDay(new Date()).getTime();
    const next = (occurrencesByCategory.get(id) ?? []).find(o => o.date.getTime() > today);
    return next ? next.date.getDate() : null;
  }

  function fixedLabel(status: (typeof fixed)[number]): { text: string; tone: "negative" | "positive" | "" } {
    if (status.state === "exceeded") return { text: `dépassé de ${budgetEuros(status.overspent)}`, tone: "negative" };
    if (status.spent >= status.budget) return { text: "✓ payé", tone: "positive" };
    const day = nextDay(status.id);
    return { text: day !== null ? `reste ${budgetEuros(status.remaining)} · le ${day}` : `reste ${budgetEuros(status.remaining)}`, tone: "" };
  }

  const barColor = (state: string, colorIndex: number) =>
    state === "ok" ? categoryColor(colorIndex) : state === "warning" ? "var(--warning)" : "var(--negative)";
</script>

{#snippet envelope(status: (typeof statuses)[number], text: string, tone: string, color: string)}
  <button type="button" class="envelope" aria-label={`${status.category.label} : modifier le budget`} onclick={() => (editing = status.id)}>
    <CategoryBadge icon={status.category.icon} colorIndex={status.category.colorIndex} />
    <div class="body">
      <div class="head">
        <span class="truncate">{status.category.label}</span>
        <span class="caption nums" class:negative={tone === "negative"} class:positive={tone === "positive"}>{text}</span>
      </div>
      <div class="gauge-box">
        <div class="track"></div>
        <div class="fill" style:width="{Math.min(1, Math.max(0, status.ratio)) * 100}%" style:background={color}></div>
      </div>
    </div>
  </button>
{/snippet}

{#if statuses.length > 0}
  <Card>
    <span class="title">Enveloppes</span>
    {#if fixed.length > 0}
      <div class="line subhead">
        <span class="caption">Charges fixes</span>
        <span class="caption nums">payé {budgetEuros(fixedSpent)} sur {budgetEuros(fixedBudget)}</span>
      </div>
      {#each fixed as status (status.id)}
        {@const label = fixedLabel(status)}
        {@render envelope(status, label.text, label.tone, status.state === "exceeded" ? "var(--negative)" : categoryColor(status.category.colorIndex))}
      {/each}
      {#if regular.length > 0}<span class="caption">Dépenses courantes</span>{/if}
    {/if}
    {#each regular as status (status.id)}
      {@const exceeded = status.state === "exceeded"}
      {@render envelope(status, exceeded ? `dépassé de ${budgetEuros(status.overspent)}` : `reste ${budgetEuros(status.remaining)}`,
                        exceeded ? "negative" : "", barColor(status.state, status.category.colorIndex))}
    {/each}
    <AddBudgetMenu {month} onpick={id => (editing = id)} />
  </Card>
{/if}

{#if editing}<EnvelopeEditorSheet categoryID={editing} {month} onclose={() => (editing = null)} />{/if}

<style>
  .subhead { display: flex; justify-content: space-between; align-items: baseline; gap: var(--spacing); }
  .envelope {
    display: flex; align-items: center; gap: var(--spacing); width: 100%; border: none; background: transparent;
    padding: 0; color: inherit; text-align: left; font: inherit;
  }
  .body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; }
  .head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--spacing); }
  .gauge-box { position: relative; height: 5px; }
  .track, .fill { position: absolute; left: 0; top: 0; height: 5px; border-radius: calc(var(--radius-small) / 2); }
  .track { width: 100%; background: var(--surface-secondary); }
</style>
