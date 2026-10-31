<script lang="ts">
  // Carte arrondie sur fond `surface` (Card de Components.swift). `hero` = carte mise en avant (HeroCard),
  // `onclick` = carte entière cliquable.
  import type { Snippet } from "svelte";

  let { children, hero = false, padded = true, onclick, class: className = "" }: {
    children: Snippet; hero?: boolean; padded?: boolean; onclick?: () => void; class?: string;
  } = $props();
</script>

{#if onclick}
  <button type="button" class="card {className}" class:hero class:padded class:clickable={true} {onclick}>
    {@render children()}
  </button>
{:else}
  <div class="card {className}" class:hero class:padded>
    {@render children()}
  </div>
{/if}

<style>
  .card {
    display: flex; flex-direction: column; gap: var(--spacing); width: 100%; min-width: 0;
    background: var(--surface); border-radius: var(--radius);
    border: var(--card-border-width) solid var(--card-border); box-shadow: var(--card-shadow);
    text-align: left; color: inherit; font: inherit;
  }
  .padded { padding: var(--padding); }
  .hero {
    background: linear-gradient(135deg, var(--hero-start), var(--hero-end));
    box-shadow: var(--hero-shadow);
    color: var(--hero-text-primary);
  }
  button.card { appearance: none; }
  .clickable:hover { filter: brightness(0.985); }
  :global([data-scheme="dark"]) .clickable:hover { filter: brightness(1.12); }
</style>
