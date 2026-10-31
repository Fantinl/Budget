<script lang="ts">
  // Ouvre le bon éditeur pour une opération : virement → éditeur de virement, sinon formulaire classique.
  // Port de OperationEditor.swift.
  import type { Draft } from "../../lib/drafts";
  import TransactionForm from "./TransactionForm.svelte";
  import TransferEditor from "./TransferEditor.svelte";

  let { draft, onclose }: { draft: Draft; onclose: () => void } = $props();
</script>

{#if draft.transaction.transferID && !draft.isNew}
  <TransferEditor transferID={draft.transaction.transferID} {onclose} />
{:else}
  <TransactionForm {draft} {onclose} />
{/if}
