<script lang="ts">
  // Formulaire d'une opération (nouvelle ou existante). Port de TransactionFormView.swift.
  import { untrack } from "svelte";
  import { type Account, type Category, type Kind, type Tag, type Transaction, MAIN_ACCOUNT_ID, kindLabel, resolvedAccountID } from "../../lib/model";
  import type { Draft } from "../../lib/drafts";
  import { store } from "../../lib/app.svelte";
  import { amountInput } from "../../lib/format";
  import { positiveAmount } from "../../lib/logic/amountExpression";
  import { addTag } from "../../lib/logic/tags";
  import Sheet from "../../ui/Sheet.svelte";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import AccountBadge from "../../ui/AccountBadge.svelte";
  import TagChip from "../../ui/TagChip.svelte";
  import DateField from "../../ui/DateField.svelte";
  import AmountField from "./AmountField.svelte";
  import AmountHint from "./AmountHint.svelte";

  let { draft, onclose }: { draft: Draft; onclose: () => void } = $props();

  const initial = untrack(() => draft);
  const isNew = initial.isNew;
  let transaction = $state.raw<Transaction>({ ...initial.transaction });
  let amountText = $state(initial.isNew ? "" : amountInput(initial.transaction.amountCents));
  let newTagName = $state("");

  /// Accepte un nombre ou un calcul (« 12,5+8 »). null si le résultat n'est pas positif.
  const parsedAmount = $derived(positiveAmount(amountText));

  const kinds: Kind[] = ["expense", "income"];

  function setKind(kind: Kind) {
    transaction = { ...transaction, kind };
    if (store.categoryOf(transaction).kind !== kind) {
      transaction = { ...transaction, categoryID: store.categoriesFor(kind)[0]?.id ?? "" };
    }
  }

  /// Catégories proposées ; une catégorie masquée reste affichée si l'opération l'utilise déjà.
  const availableCategories = $derived.by((): Category[] => {
    const visible = store.categoriesFor(transaction.kind);
    const current = store.categoryOf(transaction);
    return visible.some(c => c.id === current.id) || current.kind !== transaction.kind ? visible : [...visible, current];
  });

  /// Comptes proposés : les sélectionnables, plus celui de l'opération s'il est archivé ou Izly.
  const availableAccounts = $derived.by((): Account[] => {
    const current = store.account(transaction.accountID);
    const active = store.selectableAccounts;
    return active.some(a => a.id === current.id) ? active : [...active, current];
  });

  const hasTag = (tag: Tag) => (transaction.tagIDs ?? []).includes(tag.id);

  function toggleTag(tag: Tag) {
    const ids = transaction.tagIDs ?? [];
    const next = ids.includes(tag.id) ? ids.filter(id => id !== tag.id) : [...ids, tag.id];
    transaction = { ...transaction, tagIDs: next.length === 0 ? null : next };
  }

  const hasNewTag = $derived(newTagName.trim().length > 0);

  function addNewTag() {
    if (!hasNewTag) return;
    const tag = addTag(store, newTagName);
    if (!hasTag(tag)) toggleTag(tag);
    newTagName = "";
  }

  function save() {
    const amountCents = parsedAmount;
    if (amountCents === null) return;
    if (hasNewTag) addNewTag();
    store.upsert({
      ...transaction,
      // Compte principal = null (compatibilité avec les anciens fichiers).
      accountID: transaction.accountID === MAIN_ACCOUNT_ID ? null : transaction.accountID,
      amountCents,
      note: transaction.note.trim(),
    });
    onclose();
  }

  function remove() {
    store.delete(transaction);
    onclose();
  }
</script>

<Sheet title={isNew ? "Nouvelle opération" : "Modifier"} {onclose} width={460}>
  <div class="amount-block">
    <AmountField bind:value={amountText} onenter={save} />
    <AmountHint text={amountText} />
  </div>

  <div class="segmented type" role="group" aria-label="Type">
    {#each kinds as kind (kind)}
      <button type="button" class:selected={transaction.kind === kind} onclick={() => setKind(kind)}>{kindLabel[kind]}</button>
    {/each}
  </div>

  <Card>
    <div class="category-grid">
      {#each availableCategories as category (category.id)}
        {@const selected = transaction.categoryID === category.id}
        <button type="button" class="category" onclick={() => (transaction = { ...transaction, categoryID: category.id })}>
          <span class="ring" class:selected><CategoryBadge icon={category.icon} colorIndex={category.colorIndex} /></span>
          <span class="caption truncate" class:primary={selected}>{category.label}</span>
        </button>
      {/each}
    </div>
  </Card>

  {#if store.selectableAccounts.length > 1}
    <Card>
      <div class="col">
        <span class="caption">Compte</span>
        <div class="accounts">
          {#each availableAccounts as account (account.id)}
            {@const selected = resolvedAccountID(transaction) === account.id}
            <button type="button" class="account" class:selected onclick={() => (transaction = { ...transaction, accountID: account.id })}>
              <AccountBadge {account} size={24} />
              <span class="caption truncate" class:primary={selected}>{account.name}</span>
            </button>
          {/each}
        </div>
      </div>
    </Card>
  {/if}

  <Card>
    <DateField value={transaction.date} onchange={(d) => (transaction = { ...transaction, date: d })} />
  </Card>

  <Card>
    <div class="col">
      {#if store.tags.length > 0}
        <span class="caption">Tags</span>
        <div class="tags">
          {#each store.tags as tag (tag.id)}
            <button type="button" class="tag" onclick={() => toggleTag(tag)}>
              <TagChip text={tag.name} colorIndex={tag.colorIndex} selected={hasTag(tag)} />
            </button>
          {/each}
        </div>
      {/if}
      <input class="bare" type="text" placeholder="Nouveau tag" aria-label="Nouveau tag" bind:value={newTagName}
             onkeydown={(e) => { if (e.key === "Enter") { e.preventDefault(); addNewTag(); } }} />
    </div>
  </Card>

  <Card>
    <textarea class="bare" rows="2" placeholder="Facultatif" aria-label="Description" value={transaction.note}
              oninput={(e) => (transaction = { ...transaction, note: e.currentTarget.value })}></textarea>
  </Card>

  {#if !isNew}
    <button type="button" class="delete" onclick={remove}>Supprimer</button>
  {/if}

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={parsedAmount === null} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .amount-block { display: flex; flex-direction: column; }
  .type { align-self: stretch; display: flex; }
  .type button { flex: 1; }
  .category-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(76px, 1fr)); gap: var(--spacing); }
  .category {
    display: flex; flex-direction: column; align-items: center; gap: 6px; border: none; background: transparent;
    padding: 2px 0; min-width: 0; color: inherit;
  }
  .category .caption { max-width: 100%; }
  .caption.primary { color: var(--text-primary); }
  .ring { border-radius: 50%; padding: 3px; border: 2px solid transparent; display: inline-flex; }
  .ring.selected { border-color: var(--accent); }
  .accounts { display: flex; gap: var(--spacing); overflow-x: auto; padding: 2px; }
  .account {
    display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; max-width: 220px;
    padding: 6px var(--spacing); border-radius: 999px; background: var(--surface-secondary);
    border: 1.5px solid transparent; color: inherit;
  }
  .account.selected { background: color-mix(in srgb, var(--accent) 15%, transparent); border-color: var(--accent); }
  .tags { display: grid; grid-template-columns: repeat(auto-fill, minmax(70px, max-content)); gap: var(--spacing); }
  .tag { border: none; background: transparent; padding: 0; justify-self: start; max-width: 100%; }
  .bare {
    width: 100%; border: none; outline: none; background: transparent; padding: 0; resize: vertical;
    color: var(--text-primary); font-size: var(--body);
  }
  .bare::placeholder { color: var(--text-tertiary); }
  .delete { align-self: center; border: none; background: transparent; color: var(--negative); padding: 6px; }
</style>
