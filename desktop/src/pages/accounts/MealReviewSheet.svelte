<script lang="ts">
  // Revue hebdomadaire : « As-tu mangé au Crous ces jours-là ? » (MealReviewSheet.swift).
  import { onMount } from "svelte";
  import { store } from "../../lib/app.svelte";
  import { addDays, startOfDay } from "../../lib/dates";
  import { euros } from "../../lib/format";
  import { DEFAULT_MEAL_PRICE_CENTS } from "../../lib/model";
  import { applyMealReview, mealReviewDays, mealsOf } from "../../lib/logic/meals";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import Sheet from "../../ui/Sheet.svelte";
  import AdjustBalanceSheet from "./AdjustBalanceSheet.svelte";

  const dayFormat = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" });
  /// « Vendredi 30 Octobre » (chaque mot capitalisé, comme `.capitalized`).
  const dayLabel = (d: Date) => dayFormat.format(d).replace(/(^|\s)(\p{L})/gu, (_, sp, ch) => sp + ch.toUpperCase());

  let { accountID, onclose }: { accountID: string; onclose: () => void } = $props();

  let days = $state.raw<Date[]>([]);
  let present = $state.raw<Set<number>>(new Set());
  let showAdjust = $state(false);

  const account = $derived(store.account(accountID));
  const price = $derived(account.mealPlan?.priceCents ?? DEFAULT_MEAL_PRICE_CENTS);
  const count = $derived(days.filter(d => present.has(d.getTime())).length);

  onMount(() => {
    days = mealReviewDays(store, account);
    if (days.length === 0) return;
    const interval = { start: days[0], end: addDays(days[days.length - 1], 1) };
    present = new Set(mealsOf(store, account, interval).map(t => startOfDay(t.date).getTime()));
  });

  function toggle(day: Date) {
    const next = new Set(present);
    if (next.has(day.getTime())) next.delete(day.getTime()); else next.add(day.getTime());
    present = next;
  }

  function validate() {
    applyMealReview(store, account, days, days.filter(d => present.has(d.getTime())));
    onclose();
  }
</script>

<Sheet title="Revue de la semaine" {onclose} width={420}>
  <div class="title">As-tu mangé au Crous ces jours-là ?</div>
  {#if days.length === 0}
    <div class="secondary">Aucun jour à vérifier.</div>
  {:else}
    <Card padded={false}>
      <div class="list">
        {#each days as day, index (day.getTime())}
          {@const isOn = present.has(day.getTime())}
          {#if index > 0}<hr class="separator" />{/if}
          <button type="button" class="day" role="checkbox" aria-checked={isOn} onclick={() => toggle(day)}>
            {#if isOn}<Icon name="checkmark.circle.fill" size={18} color="var(--accent)" />{:else}<span class="ring"></span>{/if}
            <span>{dayLabel(day)}</span>
          </button>
        {/each}
      </div>
    </Card>
  {/if}
  <div class="title nums summary">{count} repas · {euros(price * count)}</div>
  <div class="summary"><button type="button" class="btn" onclick={() => (showAdjust = true)}>Ajuster avec le solde réel…</button></div>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Plus tard</button>
    <button type="button" class="btn primary" onclick={validate}>Valider</button>
  {/snippet}
</Sheet>

{#if showAdjust}<AdjustBalanceSheet {account} onclose={() => (showAdjust = false)} />{/if}

<style>
  .list { display: flex; flex-direction: column; }
  .day {
    display: flex; align-items: center; gap: var(--spacing); padding: var(--spacing) var(--padding);
    border: none; background: transparent; color: var(--text-primary); text-align: left;
  }
  .day:hover { background: var(--surface-secondary); }
  .ring { width: 18px; height: 18px; border-radius: 50%; border: 1.5px solid var(--text-tertiary); flex-shrink: 0; }
  .summary { text-align: center; }
</style>
