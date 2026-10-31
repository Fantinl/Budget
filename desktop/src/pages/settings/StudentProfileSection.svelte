<script lang="ts">
  // Section « Profil » des réglages. Port de StudentProfileSection.swift.
  import { store } from "../../lib/app.svelte";
  import { prefs } from "../../lib/prefs.svelte";
  import { currentTheme } from "../../lib/theme.svelte";
  import { makeIzly, upsertAccount } from "../../lib/logic/accounts";
  import Icon from "../../ui/Icon.svelte";
  import Group from "./Group.svelte";
  import Toggle from "./Toggle.svelte";

  const hasIzly = $derived(store.accounts.some(a => a.kind === "izly"));
</script>

<Group header="Profil" footer="Active le compte Izly et les repas Crous.">
  <Toggle label="Je suis étudiant" bind:checked={prefs.studentProfile.value} />
  {#if prefs.studentProfile.value && !hasIzly}
    <button type="button" class="add" onclick={() => upsertAccount(store, makeIzly(store.accounts, currentTheme().categoryPalette.length))}>
      <Icon name="plus.circle.fill" size={18} color="var(--accent)" />
      <span class="accent">Ajouter mon compte Izly</span>
    </button>
  {/if}
</Group>

<style>
  .add { width: 100%; border: none; background: transparent; color: inherit; text-align: left; display: flex; align-items: center; gap: 8px; }
  .accent { color: var(--accent); }
</style>
