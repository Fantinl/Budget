<script lang="ts">
  // Carte « Repas automatiques » du compte Izly (MealPlanCard.swift).
  import { onMount } from "svelte";
  import { store } from "../../lib/app.svelte";
  import { fromInputDate, toInputDate } from "../../lib/dates";
  import { amountInput } from "../../lib/format";
  import { defaultMealPlan, type MealPlan } from "../../lib/model";
  import { upsertAccount } from "../../lib/logic/accounts";
  import { generateDueMeals, parseMealPrice } from "../../lib/logic/meals";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import MealPeriodSheet from "./MealPeriodSheet.svelte";
  import MealReviewSheet from "./MealReviewSheet.svelte";
  import MealWeekdayPicker from "./MealWeekdayPicker.svelte";

  let { accountID }: { accountID: string } = $props();

  let priceText = $state("");
  let showReview = $state(false);
  let showPeriod = $state(false);

  const account = $derived(store.account(accountID));
  const plan = $derived<MealPlan>(account.mealPlan ?? { ...defaultMealPlan(), isEnabled: false });

  onMount(() => { priceText = amountInput(plan.priceCents); });

  /// Modifie le plan puis enregistre le compte.
  function update(change: Partial<MealPlan>) {
    const next: MealPlan = { ...(account.mealPlan ?? defaultMealPlan()), ...change };
    upsertAccount(store, { ...account, mealPlan: next });
    if (next.isEnabled) generateDueMeals(store);
  }

  function onPrice(text: string) {
    priceText = text;
    const cents = parseMealPrice(text);
    if (cents !== null && cents !== plan.priceCents) update({ priceCents: cents });
  }
</script>

<Card>
  <div class="col" style="gap: var(--padding)">
    <label class="line toggle">
      <span class="col tight">
        <span class="title">Repas automatiques</span>
        <span class="caption">Un repas décompté chaque jour choisi.</span>
      </span>
      <input type="checkbox" class="switch" checked={plan.isEnabled}
             onchange={(e) => { if (e.currentTarget.checked !== plan.isEnabled) update({ isEnabled: e.currentTarget.checked }); }} />
    </label>

    {#if plan.isEnabled}
      <div class="line center">
        <span>Prix du repas</span>
        <span class="row tight">
          <input class="field price" type="text" inputmode="decimal" placeholder="1,00" value={priceText}
                 oninput={(e) => onPrice(e.currentTarget.value)} aria-label="Prix du repas" />
          <span class="secondary">€</span>
        </span>
      </div>
      <div class="col tight">
        <span class="caption">Jours</span>
        <MealWeekdayPicker weekdays={plan.weekdays} onchange={(weekdays) => update({ weekdays })} />
      </div>
      <div class="line center">
        <span>À partir du</span>
        <input class="field" type="date" value={toInputDate(plan.startDate)} aria-label="À partir du"
               onchange={(e) => { const d = fromInputDate(e.currentTarget.value); if (d) update({ startDate: d }); }} />
      </div>
    {/if}

    <div class="row buttons caption">
      {#if plan.isEnabled}
        <button type="button" class="btn small" disabled={account.isArchived} onclick={() => (showReview = true)}>
          <Icon name="checklist" size={13} /> Revue de la semaine
        </button>
      {/if}
      <button type="button" class="btn small" disabled={account.isArchived} onclick={() => (showPeriod = true)}>
        <Icon name="calendar.badge.plus" size={13} /> Ajouter des repas sur une période…
      </button>
    </div>
  </div>
</Card>

{#if showReview}<MealReviewSheet {accountID} onclose={() => (showReview = false)} />{/if}
{#if showPeriod}<MealPeriodSheet {accountID} onclose={() => (showPeriod = false)} />{/if}

<style>
  .toggle { align-items: center; }
  .center { align-items: center; }
  .price { width: 80px; text-align: right; }
  .buttons { flex-wrap: wrap; }
</style>
