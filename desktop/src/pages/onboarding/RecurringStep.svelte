<script lang="ts">
  // Étape « Opérations récurrentes » (OnboardingRecurringStep).
  import { store } from "../../lib/app.svelte";
  import { type Kind, fallbackCategoryID, kindLabel } from "../../lib/model";
  import { euros } from "../../lib/format";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Check from "./Check.svelte";
  import NumberField from "./NumberField.svelte";
  import StepHeader from "./StepHeader.svelte";
  import { type RecurringItem, customRecurring } from "./items";

  let { items }: { items: RecurringItem[] } = $props();

  const kinds: Kind[] = ["expense", "income"];
  /// Noms déjà couverts par une récurrente existante.
  const existingNames = $derived(new Set(store.recurringOperations.map(r => r.name.toLowerCase())));
  const visible = $derived(items.filter(i => i.isCustom || !existingNames.has(i.name.toLowerCase())));

  function setKind(item: RecurringItem, kind: Kind) {
    item.kind = kind;
    item.categoryID = store.fallbackCategory(kind).id;
  }
</script>

<div class="col" style:gap="var(--padding)">
  <StepHeader title="Opérations récurrentes"
              subtitle="Loyer, salaire, abonnements… Coche ce qui revient chaque mois : elles seront ajoutées automatiquement à partir de la prochaine échéance. Facultatif." />

  {#if store.recurringOperations.length > 0}
    <Card>
      <span class="caption">Déjà configurées</span>
      {#each store.recurringOperations as operation (operation.id)}
        {@const category = store.category(operation.categoryID)}
        <div class="row">
          <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={30} />
          <span class="truncate">{operation.name}</span>
          <span class="spacer"></span>
          <span class="amount secondary">{euros(operation.amountCents)}</span>
        </div>
      {/each}
    </Card>
  {/if}

  <Card>
    {#each visible as item (item.id)}
      {@const category = store.category(item.categoryID)}
      <div class="row item" class:off={!item.selected}>
        <Check bind:checked={item.selected} label={item.name || "Inclure"} />
        <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={30} />
        {#if item.isCustom}
          <div class="texts grow">
            <input class="plain" placeholder="Nom de l’opération" aria-label="Nom" bind:value={item.name} />
            <div class="row tight">
              <select class="field small" aria-label="Type" value={item.kind} onchange={(e) => setKind(item, e.currentTarget.value as Kind)}>
                {#each kinds as k (k)}<option value={k}>{kindLabel[k]}</option>{/each}
              </select>
              <select class="field small" aria-label="Catégorie" bind:value={item.categoryID}>
                {#each store.categoriesFor(item.kind) as c (c.id)}<option value={c.id}>{c.label}</option>{/each}
              </select>
            </div>
          </div>
        {:else}
          <div class="texts grow">
            <span class="truncate">{item.name}</span>
            <span class="caption truncate">{category.label}</span>
          </div>
        {/if}
        <NumberField title="Montant" bind:value={item.amountText} unit="€" />
        <span class="day"><span class="secondary">le</span><NumberField title="Jour du mois" bind:value={item.dayText} unit="" width={28} /></span>
      </div>
      <hr class="separator" />
    {/each}
    <button type="button" class="add" onclick={() => items.push(customRecurring(fallbackCategoryID("expense")))}>
      <Icon name="plus.circle.fill" size={18} color="var(--accent)" /> <span>Ajouter une opération</span>
    </button>
  </Card>
</div>

<style>
  .item.off { opacity: 0.7; }
  .texts { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
  .grow { flex: 1; }
  .plain { border: none; outline: none; background: transparent; color: var(--text-primary); width: 100%; padding: 2px 0; }
  .small { height: 24px; font-size: var(--caption); max-width: 150px; }
  .day { display: inline-flex; align-items: center; gap: 4px; flex-shrink: 0; }
  .add { border: none; background: transparent; padding: 0; color: var(--accent); display: flex; align-items: center; gap: 8px; text-align: left; }
</style>
