<script lang="ts">
  // Ligne d'une opération (listes des opérations et du détail d'un compte). Port de TransactionRow.swift.
  import { type Transaction, isTransfer, signedCents } from "../lib/model";
  import { store } from "../lib/app.svelte";
  import { euros } from "../lib/format";
  import { counterpartAccount, DEFAULT_TRANSFER_NOTE } from "../lib/logic/transfers";
  import { tagsOf } from "../lib/logic/tags";
  import CategoryBadge from "./CategoryBadge.svelte";
  import TagChip from "./TagChip.svelte";
  import Icon from "./Icon.svelte";

  let { transaction, showAccount = false }: {
    transaction: Transaction;
    /// Affiche le nom du compte (plusieurs comptes et filtre « Tous »).
    showAccount?: boolean;
  } = $props();

  const category = $derived(store.categoryOf(transaction));
  const transfer = $derived(isTransfer(transaction));
  const tags = $derived(tagsOf(store, transaction));

  /// « Virement vers Livret A » (sortant) ou « Virement depuis Compte courant » (entrant).
  const transferTitle = $derived.by(() => {
    const name = counterpartAccount(store, transaction)?.name;
    const direction = transaction.kind === "expense" ? "vers" : "depuis";
    return name ? `Virement ${direction} ${name}` : "Virement";
  });

  const showNote = $derived(transaction.note.length > 0 && !(transfer && transaction.note === DEFAULT_TRANSFER_NOTE));
  const amount = $derived((transaction.kind === "income" ? "+" : "") + euros(signedCents(transaction)));
</script>

<div class="row-content">
  {#if transfer}
    <span class="transfer-badge"><Icon name="arrow.left.arrow.right" size={Math.round(34 * 0.5)} /></span>
  {:else}
    <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} />
  {/if}

  <div class="texts">
    <span class="label truncate">{transfer ? transferTitle : category.label}</span>
    {#if showNote}<span class="caption note">{transaction.note}</span>{/if}
    {#if tags.length > 0}
      <span class="tags">
        {#each tags.slice(0, 3) as tag (tag.id)}<TagChip text={tag.name} colorIndex={tag.colorIndex} selected={false} />{/each}
        {#if tags.length > 3}<span class="caption tertiary">+{tags.length - 3}</span>{/if}
      </span>
    {/if}
    {#if showAccount}<span class="caption tertiary truncate">{store.account(transaction.accountID).name}</span>{/if}
  </div>

  <span class="amount" class:secondary={transfer} class:positive={!transfer && transaction.kind === "income"}>{amount}</span>
</div>

<style>
  .row-content { display: flex; align-items: center; gap: var(--spacing); flex: 1; min-width: 0; text-align: left; }
  .texts { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; align-items: flex-start; }
  .label { max-width: 100%; }
  .note { display: -webkit-box; -webkit-line-clamp: 2; line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; max-width: 100%; }
  .tags { display: flex; align-items: center; gap: 4px; max-width: 100%; }
  .transfer-badge {
    width: var(--icon-size); height: var(--icon-size); border-radius: 50%; flex-shrink: 0;
    display: inline-flex; align-items: center; justify-content: center;
    background: var(--surface-secondary); color: var(--text-secondary);
  }
</style>
