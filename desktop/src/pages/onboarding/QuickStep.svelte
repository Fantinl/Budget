<script lang="ts">
  // Étape « Ajouts rapides » (OnboardingQuickStep).
  import { store } from "../../lib/app.svelte";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Check from "./Check.svelte";
  import NumberField from "./NumberField.svelte";
  import StepHeader from "./StepHeader.svelte";
  import type { QuickItem } from "./items";

  let { items }: { items: QuickItem[] } = $props();
</script>

<div class="col" style:gap="var(--padding)">
  <StepHeader title="Ajouts rapides"
              subtitle="Des boutons pour saisir en un clic tes dépenses habituelles. Décoche ce qui ne te sert pas, ajuste les montants. Facultatif." />
  <Card>
    {#each items as item, index (item.id)}
      {@const category = store.category(item.categoryID)}
      <div class="row" class:off={!item.selected}>
        <Check bind:checked={item.selected} label={item.name} />
        <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={30} />
        <div class="texts">
          <span class="truncate">{item.name}</span>
          <span class="caption truncate">{category.label}</span>
        </div>
        <span class="spacer"></span>
        <NumberField title="Montant" bind:value={item.amountText} unit="€" />
      </div>
      {#if index < items.length - 1}<hr class="separator" />{/if}
    {/each}
  </Card>
</div>

<style>
  .off { opacity: 0.7; }
  .texts { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
</style>
