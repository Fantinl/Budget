<script lang="ts">
  // Champ de montant (ou de nombre) aligné à droite, avec unité (OnboardingNumberField).
  let { title, value = $bindable(""), unit, width = 72 }: { title: string; value?: string; unit: string; width?: number } = $props();
</script>

<span class="nf">
  <input class="num" aria-label={title} placeholder="" inputmode="decimal" bind:value style:width="{width}px" />
  {#if unit}<span class="secondary">{unit}</span>{/if}
</span>

<style>
  .nf { display: inline-flex; align-items: center; gap: 4px; flex-shrink: 0; }
  .num {
    text-align: right; border: none; outline: none; padding: 5px 8px; border-radius: var(--radius-small);
    background: var(--surface-secondary); color: var(--text-primary);
  }
  .num:focus { box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent) 40%, transparent); }
</style>
