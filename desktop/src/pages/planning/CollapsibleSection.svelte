<script lang="ts">
  // Section repliable de la page Budget : chevron, titre et résumé court ; l'état est mémorisé (préférence).
  import type { Snippet } from "svelte";
  import type { Pref } from "../../lib/prefs.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";

  let { title, open, summary = "", summaryColor, children }: {
    title: string; open: Pref<boolean>; summary?: string; summaryColor?: string; children: Snippet;
  } = $props();
</script>

<Card>
  <button type="button" class="head" aria-expanded={open.value} onclick={() => (open.value = !open.value)}>
    <span class="chevron" class:open={open.value}><Icon name="chevron.right" size={12} color="var(--text-tertiary)" /></span>
    <span class="title grow">{title}</span>
    {#if summary}<span class="caption nums" style:color={summaryColor}>{summary}</span>{/if}
  </button>
  {#if open.value}{@render children()}{/if}
</Card>

<style>
  .head {
    display: flex; align-items: center; gap: var(--spacing); width: 100%; border: none; background: transparent;
    padding: 0; color: inherit; text-align: left; font: inherit;
  }
  .grow { flex: 1; min-width: 0; }
  .chevron { display: inline-flex; transition: transform 0.15s; }
  .chevron.open { transform: rotate(90deg); }
</style>
