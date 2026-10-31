<script lang="ts">
  // Pastilles des filtres actifs, supprimables une à une (FilterChips de FilterModel.swift).
  import { store } from "../../lib/app.svelte";
  import { euros } from "../../lib/format";
  import { type OperationFilter, emptyFilter, filterKindLabel, isFilterActive } from "../../lib/logic/filter";
  import Icon from "../../ui/Icon.svelte";

  let { filter = $bindable() }: { filter: OperationFilter } = $props();

  const categories = $derived([...filter.categoryIDs].sort());
  const tags = $derived(store.tags.filter(t => filter.tagIDs.includes(t.id)));
</script>

{#snippet chip(text: string, remove: () => void)}
  <button type="button" class="chip caption" title="Retirer ce filtre" onclick={remove}>
    <span>{text}</span><Icon name="xmark" size={10} />
  </button>
{/snippet}

{#if isFilterActive(filter)}
  <div class="chips">
    {#if filter.kind !== "all"}{@render chip(filterKindLabel[filter.kind], () => (filter = { ...filter, kind: "all" }))}{/if}
    {#each categories as id (id)}
      {@render chip(store.category(id).label, () => (filter = { ...filter, categoryIDs: filter.categoryIDs.filter(c => c !== id) }))}
    {/each}
    {#each tags as tag (tag.id)}
      {@render chip(`#${tag.name}`, () => (filter = { ...filter, tagIDs: filter.tagIDs.filter(x => x !== tag.id) }))}
    {/each}
    {#if filter.accountID !== null}
      {@render chip(store.account(filter.accountID).name, () => (filter = { ...filter, accountID: null }))}
    {/if}
    {#if filter.minCents !== null}{@render chip(`≥ ${euros(filter.minCents)}`, () => (filter = { ...filter, minCents: null }))}{/if}
    {#if filter.maxCents !== null}{@render chip(`≤ ${euros(filter.maxCents)}`, () => (filter = { ...filter, maxCents: null }))}{/if}
    <button type="button" class="clear caption" onclick={() => (filter = emptyFilter())}>Effacer les filtres</button>
  </div>
{/if}

<style>
  .chips { display: flex; gap: var(--spacing); overflow-x: auto; padding: 0 2px; scrollbar-width: none; align-items: center; }
  .chips::-webkit-scrollbar { display: none; }
  .chip {
    display: inline-flex; align-items: center; gap: 4px; flex-shrink: 0; border: none; white-space: nowrap;
    color: var(--accent); padding: 5px var(--spacing); border-radius: 999px;
    background: color-mix(in srgb, var(--accent) 12%, transparent);
  }
  .clear { border: none; background: transparent; color: var(--accent); flex-shrink: 0; white-space: nowrap; padding: 0; }
</style>
