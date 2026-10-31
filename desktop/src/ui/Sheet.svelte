<script lang="ts">
  // Feuille modale (équivalent de `.sheet` en SwiftUI) : voile, panneau centré, titre, contenu défilant,
  // boutons en bas. Échap ferme (sauf `dismissable = false`). Afficher avec {#if …}<Sheet …/>{/if}.
  import type { Snippet } from "svelte";

  let { title, onclose, children, footer, width = 520, dismissable = true }: {
    title?: string;
    onclose: () => void;
    children: Snippet;
    /// Boutons du bas (Annuler / Enregistrer…).
    footer?: Snippet;
    width?: number;
    dismissable?: boolean;
  } = $props();

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape" && dismissable) { e.stopPropagation(); onclose(); }
  }
</script>

<svelte:window {onkeydown} />

<div class="veil" role="presentation" onmousedown={(e) => { if (e.target === e.currentTarget && dismissable) onclose(); }}>
  <div class="sheet" role="dialog" aria-modal="true" aria-label={title} style:width="min({width}px, calc(100vw - 32px))">
    {#if title}<header class="title">{title}</header>{/if}
    <div class="content">{@render children()}</div>
    {#if footer}<footer>{@render footer()}</footer>{/if}
  </div>
</div>

<style>
  .veil {
    position: fixed; inset: 0; z-index: 100; display: flex; align-items: center; justify-content: center;
    background: rgba(0, 0, 0, 0.28); animation: fade 0.12s ease-out;
  }
  .sheet {
    max-height: calc(100vh - 48px); display: flex; flex-direction: column;
    background: var(--background); border-radius: calc(var(--radius) + 2px);
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3), 0 0 0 1px var(--separator);
    animation: pop 0.14s ease-out;
  }
  header { padding: var(--padding) var(--padding) 0; }
  .content { padding: var(--padding); overflow: auto; display: flex; flex-direction: column; gap: var(--spacing); }
  footer {
    display: flex; justify-content: flex-end; gap: 8px; padding: var(--spacing) var(--padding);
    border-top: 1px solid var(--separator);
  }
  @keyframes fade { from { opacity: 0; } }
  @keyframes pop { from { transform: scale(0.97); opacity: 0; } }
</style>
