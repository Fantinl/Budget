<script lang="ts">
  // Titre et sous-titre d'une étape (OnboardingStepHeader).
  let { title, subtitle }: { title: string; subtitle: string } = $props();
</script>

<div class="header">
  <h2 class="large-amount">{title}</h2>
  <p class="secondary">{subtitle}</p>
</div>

<style>
  .header { display: flex; flex-direction: column; gap: 6px; }
  h2, p { margin: 0; }
</style>
