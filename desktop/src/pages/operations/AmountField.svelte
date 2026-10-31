<script lang="ts">
  // Montant en grand, centré, suivi de « € » (champ des formulaires d'opération et de virement).
  let { value = $bindable(), onenter }: { value: string; onenter?: () => void } = $props();

  let input = $state<HTMLInputElement>();
  $effect(() => { input?.focus(); });
</script>

<div class="amount-field">
  <input bind:this={input} bind:value class="large-amount" type="text" inputmode="decimal" autocomplete="off"
         aria-label="Montant" placeholder="0,00" style:width="{Math.max(80, (value.length + 1) * 0.62 * 34)}px"
         onkeydown={(e) => { if (e.key === "Enter") { e.preventDefault(); onenter?.(); } }} />
  <span class="large-amount secondary">€</span>
</div>

<style>
  .amount-field { display: flex; align-items: baseline; justify-content: center; gap: 4px; padding: var(--spacing) 0; }
  input {
    border: none; outline: none; background: transparent; text-align: right; color: var(--text-primary);
    min-width: 80px; max-width: 100%; padding: 0;
  }
  input::placeholder { color: var(--text-tertiary); }
</style>
