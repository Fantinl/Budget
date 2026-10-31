<script lang="ts">
  // Section de réglages (Section d'un Form groupé) : titre, lignes dans une carte, note en bas.
  // Chaque enfant direct du contenu est une ligne.
  import type { Snippet } from "svelte";
  import Card from "../../ui/Card.svelte";

  let { header, footer, children }: { header?: string; footer?: string; children: Snippet } = $props();
</script>

<section class="group">
  {#if header}<h3 class="caption head">{header}</h3>{/if}
  <Card padded={false}><div class="rows">{@render children()}</div></Card>
  {#if footer}<p class="caption foot">{footer}</p>{/if}
</section>

<style>
  .group { display: flex; flex-direction: column; gap: 6px; }
  .head { margin: 0 var(--padding); font-weight: 600; text-transform: none; }
  .foot { margin: 0 var(--padding); }
  .rows { display: flex; flex-direction: column; }
  .rows > :global(*) { padding: 10px var(--padding); min-height: 40px; display: flex; align-items: center; gap: var(--spacing); }
  .rows > :global(* + *) { border-top: 1px solid var(--separator); }
</style>
