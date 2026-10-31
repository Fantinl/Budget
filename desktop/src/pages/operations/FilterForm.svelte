<script lang="ts">
  // Formulaire des filtres (popover). Port de FilterForm de FilterModel.swift.
  import type { Kind } from "../../lib/model";
  import { store } from "../../lib/app.svelte";
  import { amountInput, parseAmount } from "../../lib/format";
  import { type FilterKind, type OperationFilter, emptyFilter, filterKindLabel, filterKinds, isFilterActive, toggled } from "../../lib/logic/filter";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Icon from "../../ui/Icon.svelte";
  import { categoryColor } from "../../lib/theme.svelte";

  let { filter = $bindable(), showAccount }: {
    filter: OperationFilter;
    /// Masque le filtre par compte (vue d'un compte).
    showAccount: boolean;
  } = $props();

  let minText = $state(filter.minCents === null ? "" : amountInput(filter.minCents));
  let maxText = $state(filter.maxCents === null ? "" : amountInput(filter.maxCents));

  const kinds: Kind[] = ["expense", "income"];

  function clear() {
    filter = emptyFilter();
    minText = "";
    maxText = "";
  }
</script>

<div class="form">
  <section>
    <h4 class="caption">Type</h4>
    <div class="segmented wide" role="group" aria-label="Type">
      {#each filterKinds as k (k)}
        <button type="button" class:selected={filter.kind === k} onclick={() => (filter = { ...filter, kind: k as FilterKind })}>{filterKindLabel[k]}</button>
      {/each}
    </div>
  </section>

  {#if showAccount && store.selectableAccounts.length > 1}
    <section>
      <h4 class="caption">Compte</h4>
      <select class="field full" aria-label="Compte" value={filter.accountID ?? ""}
              onchange={(e) => (filter = { ...filter, accountID: e.currentTarget.value === "" ? null : e.currentTarget.value })}>
        <option value="">Tous</option>
        {#each store.selectableAccounts as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
      </select>
    </section>
  {/if}

  <section>
    <h4 class="caption">Montant</h4>
    <div class="col tight">
      <input class="field" type="text" inputmode="decimal" placeholder="Minimum" aria-label="Minimum" bind:value={minText}
             oninput={() => (filter = { ...filter, minCents: parseAmount(minText) })} />
      <input class="field" type="text" inputmode="decimal" placeholder="Maximum" aria-label="Maximum" bind:value={maxText}
             oninput={() => (filter = { ...filter, maxCents: parseAmount(maxText) })} />
    </div>
  </section>

  <section>
    <h4 class="caption">Catégories</h4>
    {#each kinds as kind (kind)}
      {#each store.categoriesFor(kind) as category (category.id)}
        <button type="button" class="choice" onclick={() => (filter = { ...filter, categoryIDs: toggled(filter.categoryIDs, category.id) })}>
          <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={Math.round(34 * 0.7)} />
          <span class="truncate">{category.label}</span>
          <span class="spacer"></span>
          {#if filter.categoryIDs.includes(category.id)}<Icon name="checkmark" size={14} color="var(--accent)" />{/if}
        </button>
      {/each}
    {/each}
  </section>

  {#if store.tags.length > 0}
    <section>
      <h4 class="caption">Tags</h4>
      {#each store.tags as tag (tag.id)}
        <button type="button" class="choice" onclick={() => (filter = { ...filter, tagIDs: toggled(filter.tagIDs, tag.id) })}>
          <span class="dot" style:background={categoryColor(tag.colorIndex)}></span>
          <span class="truncate">{tag.name}</span>
          <span class="spacer"></span>
          {#if filter.tagIDs.includes(tag.id)}<Icon name="checkmark" size={14} color="var(--accent)" />{/if}
        </button>
      {/each}
    </section>
  {/if}

  {#if isFilterActive(filter)}
    <button type="button" class="btn danger" onclick={clear}>Effacer les filtres</button>
  {/if}
</div>

<style>
  .form { display: flex; flex-direction: column; gap: var(--spacing); padding: var(--spacing); }
  section { display: flex; flex-direction: column; gap: 4px; }
  h4 { margin: 0 0 2px; font-weight: 600; }
  .wide { display: flex; }
  .wide button { flex: 1; padding: 0 4px; }
  .full { width: 100%; }
  .choice {
    display: flex; align-items: center; gap: var(--spacing); width: 100%; border: none; background: transparent;
    color: var(--text-primary); padding: 3px 4px; border-radius: var(--radius-small); text-align: left;
  }
  .choice:hover { background: var(--surface-secondary); }
  .dot { width: 12px; height: 12px; border-radius: 50%; flex-shrink: 0; margin: 0 11px; }
</style>
