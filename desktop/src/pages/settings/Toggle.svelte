<script lang="ts">
  // Ligne « libellé + interrupteur » (Toggle).
  let { label, checked = $bindable(false) }: { label: string; checked?: boolean } = $props();
</script>

<label class="toggle">
  <span>{label}</span>
  <input type="checkbox" class="switch" bind:checked />
</label>

<style>
  .toggle { display: flex; align-items: center; justify-content: space-between; gap: var(--spacing); width: 100%; }
</style>
