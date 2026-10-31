<script lang="ts">
  // Petit aperçu « = 20,50 € » affiché quand le champ montant contient un calcul (AmountExpressionHint).
  import { containsOperator, evaluate } from "../../lib/logic/amountExpression";
  import { euros } from "../../lib/format";

  let { text }: { text: string } = $props();
  const value = $derived(containsOperator(text) ? evaluate(text) : undefined);
</script>

{#if containsOperator(text)}
  {#if value !== null && value !== undefined}
    <span class="caption nums hint">= {euros(value)}</span>
  {:else}
    <span class="caption negative hint">Calcul invalide</span>
  {/if}
{/if}

<style>
  .hint { text-align: center; }
</style>
