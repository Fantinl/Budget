<script lang="ts">
  // Étape « Es-tu étudiant ? » et carte « Compte Izly » (OnboardingStudentStep, OnboardingIzlyCard).
  import Card from "../../ui/Card.svelte";
  import Chip from "./Chip.svelte";
  import StepHeader from "./StepHeader.svelte";

  let { isStudent = $bindable(false) }: { isStudent?: boolean } = $props();
</script>

<div class="col">
  <StepHeader title="Es-tu étudiant ?" subtitle="Si oui, on prépare un compte Izly et un ajout rapide pour tes repas Crous (1 €)." />
  <Card>
    <div class="chips">
      <Chip title="Oui" icon="graduationcap.fill" selected={isStudent} onclick={() => (isStudent = true)} />
      <Chip title="Non" selected={!isStudent} onclick={() => (isStudent = false)} />
    </div>
  </Card>
</div>

<style>
  .chips { display: flex; flex-wrap: wrap; gap: var(--spacing); }
</style>
