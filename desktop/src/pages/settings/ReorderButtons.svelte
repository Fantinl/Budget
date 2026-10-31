<script lang="ts">
  // Flèches ↑ ↓ pour réordonner une ligne (ReorderButtons de ReorderControls.swift).
  import Icon from "../../ui/Icon.svelte";

  let { canMoveUp, canMoveDown, onup, ondown }: {
    canMoveUp: boolean; canMoveDown: boolean; onup: () => void; ondown: () => void;
  } = $props();
</script>

<span class="arrows">
  <button type="button" class="arrow" title="Monter" aria-label="Monter" disabled={!canMoveUp} onclick={onup}>
    <Icon name="chevron.up" size={13} />
  </button>
  <button type="button" class="arrow" title="Descendre" aria-label="Descendre" disabled={!canMoveDown} onclick={ondown}>
    <Icon name="chevron.down" size={13} />
  </button>
</span>

<style>
  .arrows { display: inline-flex; gap: 2px; flex-shrink: 0; }
  .arrow {
    width: 22px; height: 22px; border: none; background: transparent; color: var(--text-secondary);
    display: inline-flex; align-items: center; justify-content: center; border-radius: 4px; padding: 0;
  }
  .arrow:hover:not(:disabled) { background: var(--surface-secondary); }
  .arrow:disabled { color: var(--text-tertiary); opacity: 0.4; }
</style>
