<script lang="ts">
  // Pastille sélectionnable (OnboardingChip).
  import Icon from "../../ui/Icon.svelte";

  let { title, icon, selected = false, onclick }: { title: string; icon?: string; selected?: boolean; onclick: () => void } = $props();
</script>

<button type="button" class="chip" class:selected {onclick} aria-pressed={selected}>
  {#if icon}<Icon name={icon} size={13} />{/if}
  <span class="truncate">{title}</span>
</button>

<style>
  .chip {
    display: inline-flex; align-items: center; gap: 6px; font-size: var(--caption); font-weight: var(--caption-weight);
    padding: 7px var(--spacing); border-radius: 999px; color: var(--text-secondary);
    background: var(--surface-secondary); border: 1.5px solid transparent;
  }
  .chip.selected { color: var(--text-primary); background: color-mix(in srgb, var(--accent) 15%, transparent); border-color: var(--accent); }
</style>
