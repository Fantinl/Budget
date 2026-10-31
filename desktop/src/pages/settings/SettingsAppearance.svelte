<script lang="ts">
  // Sections « Barre latérale » et « Apparence » : chiffres de la barre latérale, mode clair/sombre, choix du style.
  // Port de SettingsAppearance.swift.
  import { appearanceLabel, type AppearanceMode, prefs } from "../../lib/prefs.svelte";
  import { type Adaptive, themeNamed, themes } from "../../lib/theme.svelte";
  import Icon from "../../ui/Icon.svelte";
  import Group from "./Group.svelte";
  import Toggle from "./Toggle.svelte";

  const modes: AppearanceMode[] = ["system", "light", "dark"];

  // Mode d'affichage effectif (pour peindre les vignettes avec les couleurs du thème dans le bon mode).
  const media = typeof window !== "undefined" ? window.matchMedia("(prefers-color-scheme: dark)") : null;
  let systemDark = $state(media?.matches ?? false);
  $effect(() => {
    if (!media) return;
    const update = () => (systemDark = media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  });
  const dark = $derived(prefs.appearance.value === "dark" || (prefs.appearance.value === "system" && systemDark));
  const pick = (c: Adaptive) => (typeof c === "string" ? c : dark ? c.dark : c.light);

  const selectedID = $derived(themeNamed(prefs.themeID.value).id);
</script>

<Group header="Barre latérale" footer="Chiffres affichés en haut de la barre latérale.">
  <Toggle label="Afficher des chiffres" bind:checked={prefs.sidebarFigures.value} />
  {#if prefs.sidebarFigures.value}
    <Toggle label="Patrimoine" bind:checked={prefs.sidebarWealth.value} />
    <Toggle label="Dépensé ce mois-ci" bind:checked={prefs.sidebarSpent.value} />
    <Toggle label="Revenus du mois" bind:checked={prefs.sidebarIncome.value} />
    <Toggle label="Solde du mois" bind:checked={prefs.sidebarBalance.value} />
    <Toggle label="Nombre d’opérations du mois (à côté d’Opérations)" bind:checked={prefs.sidebarMonthCount.value} />
    <Toggle label="Nombre de comptes (à côté de Comptes)" bind:checked={prefs.sidebarAccountCount.value} />
  {/if}
</Group>

<Group header="Apparence">
  <div class="mode">
    <span class="segmented" role="group" aria-label="Mode">
      {#each modes as mode (mode)}
        <button type="button" class:selected={prefs.appearance.value === mode} onclick={() => (prefs.appearance.value = mode)}>
          {appearanceLabel[mode]}
        </button>
      {/each}
    </span>
  </div>
  <div class="wrap"><div class="themes">
    {#each themes as option (option.id)}
      {@const selected = option.id === selectedID}
      <button type="button" class="preview" class:selected aria-label={option.name} aria-pressed={selected}
              style:background={pick(option.background)} style:border-radius="{option.smallCornerRadius}px"
              style:border-color={selected ? pick(option.accent) : pick(option.separator)}
              style:border-width="{selected ? 2 : 1}px" onclick={() => (prefs.themeID.value = option.id)}>
        <span class="top">
          <span class="name" style:color={pick(option.textPrimary)} style:font-weight={option.titleWeight}>{option.name}</span>
          {#if selected}<Icon name="checkmark.circle.fill" size={16} color={pick(option.accent)} />{/if}
        </span>
        <span class="dots">
          {#each option.categoryPalette.slice(0, 4) as color, i (i)}
            <span class="dot" style:background={pick(color)}></span>
          {/each}
          <span class="pill" style:background={pick(option.accent)}></span>
        </span>
      </button>
    {/each}
  </div></div>
</Group>

<style>
  .mode { justify-content: flex-start; }
  .mode .segmented { width: 100%; }
  .mode .segmented button { flex: 1; }
  .themes { flex: 1; display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; align-items: stretch; }
  .preview {
    display: flex; flex-direction: column; gap: 8px; padding: 10px; text-align: left; border-style: solid;
    color: inherit;
  }
  .top { display: flex; align-items: center; justify-content: space-between; gap: 4px; }
  .name { font-size: var(--title); }
  .dots { display: flex; align-items: center; gap: 4px; }
  .dot { width: 12px; height: 12px; border-radius: 50%; }
  .pill { width: 18px; height: 8px; border-radius: 4px; }
</style>
