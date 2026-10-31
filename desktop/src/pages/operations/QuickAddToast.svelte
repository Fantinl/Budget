<script lang="ts">
  // Bandeau discret en bas d'écran avec annulation, masqué après ~4 s (QuickAddToastView).
  import { store } from "../../lib/app.svelte";
  import { euros } from "../../lib/format";
  import type { QuickAddToast } from "./QuickAddBar.svelte";

  let { toast, ondismiss }: { toast: QuickAddToast; ondismiss: () => void } = $props();

  $effect(() => {
    void toast.id;
    const timer = setTimeout(ondismiss, 4000);
    return () => clearTimeout(timer);
  });
</script>

<div class="toast">
  <span>{toast.name} · {euros(toast.transaction.amountCents)} ajouté</span>
  <button type="button" class="undo" onclick={() => { store.delete(toast.transaction); ondismiss(); }}>Annuler</button>
</div>

<style>
  .toast {
    display: inline-flex; align-items: center; gap: var(--spacing); padding: var(--spacing) var(--padding);
    border-radius: 999px; background: var(--surface-secondary); border: 1px solid var(--separator);
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.18); animation: rise 0.2s ease-out;
  }
  .undo { border: none; background: transparent; color: var(--accent); font-weight: 600; padding: 0; }
  @keyframes rise { from { transform: translateY(12px); opacity: 0; } }
</style>
