<script lang="ts">
  // Case ronde cochable d'une ligne de suggestion (OnboardingCheck).
  import Icon from "../../ui/Icon.svelte";

  let { checked = $bindable(false), label = "Inclure" }: { checked?: boolean; label?: string } = $props();
</script>

<button type="button" class="check" aria-pressed={checked} aria-label={label} onclick={() => (checked = !checked)}>
  <Icon name={checked ? "checkmark.circle.fill" : "circle"} size={20} color={checked ? "var(--accent)" : "var(--text-tertiary)"} />
</button>

<style>
  .check { border: none; background: transparent; padding: 0; display: inline-flex; flex-shrink: 0; }
</style>
