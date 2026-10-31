<script lang="ts" module>
  export interface MenuItem {
    label: string;
    icon?: string;
    danger?: boolean;
    disabled?: boolean;
    action: () => void;
  }
</script>

<script lang="ts">
  // Menu contextuel (clic droit / bouton « … ») à la position donnée. Se ferme au clic ailleurs, sur Échap ou après un choix.
  import Icon from "../../ui/Icon.svelte";

  let { x, y, items, onclose }: { x: number; y: number; items: MenuItem[]; onclose: () => void } = $props();

  let width = $state(220);
  let height = $state(0);
  const left = $derived(Math.max(8, Math.min(x, window.innerWidth - width - 8)));
  const top = $derived(Math.max(8, Math.min(y, window.innerHeight - height - 8)));
</script>

<svelte:window onmousedown={onclose} onblur={onclose} onkeydown={(e) => { if (e.key === "Escape") { e.stopPropagation(); onclose(); } }} />

<div class="menu" role="menu" tabindex="-1" style:left="{left}px" style:top="{top}px" bind:clientWidth={width} bind:clientHeight={height}
     onmousedown={(e) => e.stopPropagation()} oncontextmenu={(e) => e.preventDefault()}>
  {#each items as item (item.label)}
    <button type="button" role="menuitem" class="item" class:danger={item.danger} disabled={item.disabled}
            onclick={() => { onclose(); item.action(); }}>
      <span class="icon">{#if item.icon}<Icon name={item.icon} size={14} />{/if}</span>
      <span>{item.label}</span>
    </button>
  {/each}
</div>

<style>
  .menu {
    position: fixed; z-index: 150; min-width: 200px; padding: 4px; display: flex; flex-direction: column;
    background: var(--surface); border-radius: var(--radius-small);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25), 0 0 0 1px var(--separator);
  }
  .item {
    display: flex; align-items: center; gap: 8px; height: 28px; padding: 0 8px; border: none; background: transparent;
    color: var(--text-primary); border-radius: calc(var(--radius-small) - 2px); text-align: left;
  }
  .item:hover:not(:disabled) { background: var(--accent); color: var(--on-accent); }
  .item:disabled { opacity: 0.4; }
  .item.danger { color: var(--negative); }
  .item.danger:hover:not(:disabled) { color: var(--on-accent); background: var(--negative); }
  .icon { width: 16px; display: inline-flex; justify-content: center; }
</style>
