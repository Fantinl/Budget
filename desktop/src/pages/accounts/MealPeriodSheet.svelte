<script lang="ts">
  // Feuille « Ajouter des repas sur une période » (du / au, jours, prix) — MealPeriodSheet.swift.
  import { onMount } from "svelte";
  import { store } from "../../lib/app.svelte";
  import { fromInputDate, startOfDay, toInputDate } from "../../lib/dates";
  import { amountInput, euros } from "../../lib/format";
  import { DEFAULT_MEAL_PRICE_CENTS } from "../../lib/model";
  import { addMeals, mealsToAdd, parseMealPrice } from "../../lib/logic/meals";
  import Card from "../../ui/Card.svelte";
  import Sheet from "../../ui/Sheet.svelte";
  import MealWeekdayPicker from "./MealWeekdayPicker.svelte";

  let { accountID, onclose }: { accountID: string; onclose: () => void } = $props();

  let from = $state(startOfDay(new Date()));
  let to = $state(startOfDay(new Date()));
  let weekdays = $state<number[]>([2, 3, 4, 5, 6]);
  let priceText = $state("");

  const account = $derived(store.account(accountID));
  const price = $derived(parseMealPrice(priceText));
  const count = $derived(mealsToAdd(store, account, from, to, weekdays));
  const canSave = $derived(price !== null && count > 0);
  const preview = $derived(`${count} repas · ${euros((price ?? 0) * count)}`);

  onMount(() => {
    if (account.mealPlan) {
      weekdays = [...account.mealPlan.weekdays];
      priceText = amountInput(account.mealPlan.priceCents);
    } else {
      priceText = amountInput(DEFAULT_MEAL_PRICE_CENTS);
    }
  });

  function setFrom(value: string) {
    const d = fromInputDate(value);
    if (!d) return;
    from = d;
    if (to.getTime() < d.getTime()) to = d;
  }

  function setTo(value: string) {
    const d = fromInputDate(value);
    if (d && d.getTime() >= from.getTime()) to = d;
  }

  function save() {
    if (price === null || !canSave) return;
    addMeals(store, account, from, to, weekdays, price);
    onclose();
  }
</script>

<Sheet title="Ajouter des repas" {onclose} width={420}>
  <Card>
    <label class="line center"><span>Du</span>
      <input class="field" type="date" value={toInputDate(from)} onchange={(e) => setFrom(e.currentTarget.value)} /></label>
    <label class="line center"><span>Au</span>
      <input class="field" type="date" min={toInputDate(from)} value={toInputDate(to)} onchange={(e) => setTo(e.currentTarget.value)} /></label>
  </Card>
  <Card>
    <span class="caption">Jours</span>
    <MealWeekdayPicker {weekdays} onchange={(w) => (weekdays = w)} />
    <div class="line center">
      <span>Prix du repas</span>
      <span class="row tight">
        <input class="field price" type="text" inputmode="decimal" placeholder="1,00" bind:value={priceText} aria-label="Prix du repas" />
        <span class="secondary">€</span>
      </span>
    </div>
  </Card>
  <div class="title nums center-text">{preview}</div>
  <div class="caption tertiary center-text">Les jours déjà décomptés sont ignorés.</div>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Ajouter</button>
  {/snippet}
</Sheet>

<style>
  .center { align-items: center; }
  .center-text { text-align: center; }
  .price { width: 80px; text-align: right; }
</style>
