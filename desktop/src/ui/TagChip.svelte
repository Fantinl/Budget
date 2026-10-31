<script lang="ts">
  // Petite capsule colorée affichant un tag (TagChip de BudgetStore+Tags.swift).
  import { categoryColor } from "../lib/theme.svelte";

  let { text, colorIndex, selected = true }: { text: string; colorIndex: number; selected?: boolean } = $props();
</script>

<span class="chip" class:selected style:--c={categoryColor(colorIndex)}>{text}</span>

<style>
  .chip {
    display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    font-size: var(--caption); font-weight: var(--caption-weight); color: var(--text-primary);
    padding: 3px var(--spacing); border-radius: 999px;
    background: color-mix(in srgb, var(--c) 10%, transparent); border: 1px solid transparent;
  }
  .chip.selected { background: color-mix(in srgb, var(--c) 25%, transparent); border-color: var(--c); }
</style>
