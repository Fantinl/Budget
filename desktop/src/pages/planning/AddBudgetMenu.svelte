<script lang="ts">
  // Menu « Ajouter un budget » : catégories de dépense visibles sans budget ce mois-ci.
  import { store } from "../../lib/app.svelte";
  import { budgetedCategories } from "../../lib/logic/budgets";
  import Icon from "../../ui/Icon.svelte";

  let { month, onpick }: { month: Date; onpick: (categoryID: string) => void } = $props();

  let menuOpen = $state(false);
  let menu: HTMLElement | undefined = $state();

  const others = $derived.by(() => {
    const budgeted = new Set(budgetedCategories(store, month).map(c => c.id));
    return store.categories.filter(c => c.kind === "expense" && !c.isHidden && !budgeted.has(c.id));
  });

  function onwindowdown(e: MouseEvent) {
    if (menuOpen && menu && !menu.contains(e.target as Node)) menuOpen = false;
  }
</script>

<svelte:window onmousedown={onwindowdown} />

{#if others.length > 0}
  <div class="menu" bind:this={menu}>
    <button type="button" class="add caption" aria-expanded={menuOpen} onclick={() => (menuOpen = !menuOpen)}>
      <Icon name="plus.circle" size={14} color="var(--accent)" />Ajouter un budget
    </button>
    {#if menuOpen}
      <div class="menu-list" role="menu">
        {#each others as category (category.id)}
          <button type="button" role="menuitem" class="menu-item" onclick={() => { onpick(category.id); menuOpen = false; }}>{category.label}</button>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .menu { position: relative; align-self: flex-start; }
  .add { display: inline-flex; align-items: center; gap: 6px; border: none; background: transparent; padding: 0; color: var(--accent); }
  .menu-list {
    position: absolute; top: calc(100% + 4px); left: 0; z-index: 30; min-width: 200px; max-height: 280px; overflow: auto;
    padding: 4px; display: flex; flex-direction: column; background: var(--surface); border-radius: var(--radius-small);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2), 0 0 0 1px var(--separator);
  }
  .menu-item { border: none; background: transparent; text-align: left; padding: 5px 10px; border-radius: 4px; color: var(--text-primary); }
  .menu-item:hover { background: var(--accent); color: var(--on-accent); }
</style>
