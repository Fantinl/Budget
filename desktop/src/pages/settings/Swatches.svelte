<script lang="ts">
  // Choix d'une couleur de la palette du thème (grille de pastilles avec coche).
  import Icon from "../../ui/Icon.svelte";
  import { categoryColor } from "../../lib/theme.svelte";

  let { value, onselect }: { value: number; onselect: (index: number) => void } = $props();
</script>

<div class="swatches">
  {#each Array.from({ length: 12 }, (_, i) => i) as index (index)}
    <button type="button" class="swatch" style:background={categoryColor(index)} aria-label={`Couleur ${index + 1}`}
            aria-pressed={value === index} onclick={() => onselect(index)}>
      {#if value === index}<Icon name="checkmark" size={14} color="var(--surface)" strokeWidth={3} />{/if}
    </button>
  {/each}
</div>

<style>
  .swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(36px, 1fr)); gap: 8px; width: 100%; }
  .swatch {
    width: 28px; height: 28px; border-radius: 50%; border: none; padding: 0;
    display: inline-flex; align-items: center; justify-content: center;
  }
</style>
