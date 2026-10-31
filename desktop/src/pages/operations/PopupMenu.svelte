<script lang="ts" module>
  export interface MenuItem {
    label?: string;
    /// Nom de symbole SF (voir icons.ts) ; "" = espace réservé pour l'alignement.
    icon?: string;
    danger?: boolean;
    disabled?: boolean;
    /// Titre de section (non cliquable).
    header?: boolean;
    divider?: boolean;
    onclick?: () => void;
  }
</script>

<script lang="ts">
  // Menu flottant (menu contextuel, menus déroulants de la barre d'actions). Se ferme au clic extérieur,
  // sur Échap ou après un choix.
  import Icon from "../../ui/Icon.svelte";

  let { x, y, above = false, items, onclose }: {
    x: number; y: number;
    /// Le menu s'ouvre vers le haut à partir de (x, y).
    above?: boolean;
    items: MenuItem[];
    onclose: () => void;
  } = $props();

  let el = $state<HTMLDivElement>();
  let left = $state(0);
  let top = $state(0);
  let ready = $state(false);
  const hasIcons = $derived(items.some(i => i.icon !== undefined));

  $effect(() => {
    if (!el) return;
    const r = el.getBoundingClientRect();
    left = Math.max(8, Math.min(x, window.innerWidth - r.width - 8));
    const wanted = above ? y - r.height : y;
    top = Math.max(8, Math.min(wanted, window.innerHeight - r.height - 8));
    ready = true;
  });

  function pick(item: MenuItem) {
    if (item.disabled || item.header || item.divider) return;
    onclose();
    item.onclick?.();
  }

  function onwindowdown(e: MouseEvent) { if (el && !el.contains(e.target as Node)) onclose(); }
  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); onclose(); }
  }
</script>

<svelte:window onmousedowncapture={onwindowdown} onkeydowncapture={onkeydown} onblur={onclose} onresize={onclose} />

<div class="menu" bind:this={el} style:left="{left}px" style:top="{top}px" style:visibility={ready ? "visible" : "hidden"}
     role="menu" tabindex="-1" oncontextmenu={(e) => e.preventDefault()}>
  {#each items as item, i (i)}
    {#if item.divider}
      <hr class="separator" />
    {:else if item.header}
      <div class="header caption">{item.label}</div>
    {:else}
      <button type="button" role="menuitem" class="item" class:danger={item.danger} disabled={item.disabled} onclick={() => pick(item)}>
        {#if hasIcons}<span class="icon">{#if item.icon}<Icon name={item.icon} size={14} />{/if}</span>{/if}
        <span class="truncate">{item.label}</span>
      </button>
    {/if}
  {/each}
</div>

<style>
  .menu {
    position: fixed; z-index: 400; min-width: 180px; max-width: 320px; max-height: min(420px, calc(100vh - 16px));
    overflow-y: auto; padding: 4px; border-radius: var(--radius-small);
    background: var(--surface); box-shadow: 0 8px 30px rgba(0, 0, 0, 0.22), 0 0 0 1px var(--separator);
  }
  .item {
    display: flex; align-items: center; gap: 8px; width: 100%; height: 28px; padding: 0 8px; border: none;
    background: transparent; color: var(--text-primary); text-align: left; border-radius: calc(var(--radius-small) - 2px);
  }
  .item:hover:not(:disabled) { background: color-mix(in srgb, var(--accent) 16%, transparent); }
  .item:disabled { opacity: 0.4; }
  .item.danger { color: var(--negative); }
  .icon { width: 16px; display: inline-flex; justify-content: center; flex-shrink: 0; }
  .header { padding: 6px 8px 2px; color: var(--text-tertiary); }
  hr { margin: 4px 0; }
</style>
