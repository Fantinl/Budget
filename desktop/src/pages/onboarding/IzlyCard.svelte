<script lang="ts">
  // Carte « Compte Izly » de l'étape des comptes (OnboardingIzlyCard).
  import { accountKinds } from "../../lib/model";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import Check from "./Check.svelte";
  import NumberField from "./NumberField.svelte";

  let { isOn = $bindable(true), balanceText = $bindable("") }: { isOn?: boolean; balanceText?: string } = $props();
</script>

<Card>
  <div class="row">
    <Check bind:checked={isOn} label="Créer le compte Izly" />
    <Icon name={accountKinds.izly.icon} size={18} color="var(--accent)" />
    <span>Compte Izly</span>
    <span class="spacer"></span>
    {#if isOn}<NumberField title="Solde actuel" bind:value={balanceText} unit="€" width={90} />{/if}
  </div>
  <p class="caption">Ton porte-monnaie Crous, alimenté par des virements. Solde actuel facultatif.</p>
</Card>

<style>
  p { margin: 0; }
</style>
