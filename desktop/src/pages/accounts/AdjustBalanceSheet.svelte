<script lang="ts">
  // Feuille « Ajuster le solde » : on saisit le solde réel, l'écart devient une opération (AdjustBalanceSheet.swift).
  import { onMount } from "svelte";
  import { store } from "../../lib/app.svelte";
  import { euros, parseAmount } from "../../lib/format";
  import type { Account } from "../../lib/model";
  import { balance } from "../../lib/logic/accounts";
  import { adjustBalance, balanceGap } from "../../lib/logic/adjust";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import DateField from "../../ui/DateField.svelte";
  import Sheet from "../../ui/Sheet.svelte";

  let { account: initial, onclose }: { account: Account; onclose: () => void } = $props();

  let balanceText = $state("");
  let categoryID = $state("");
  let note = $state("");
  let date = $state(new Date());
  let input = $state<HTMLInputElement>();

  const account = $derived(store.account(initial.id));
  const current = $derived(balance(store, account));
  /// Accepte « 13 », « 13,50 », « 1 234,5 », « -5 » ; 0 est valide.
  const parsedBalance = $derived(balanceText.trim().length === 0 ? null : parseAmount(balanceText));
  const gap = $derived(parsedBalance === null ? null : balanceGap(store, account, parsedBalance));
  const canSave = $derived((gap ?? 0) !== 0);
  const defaultNote = $derived(
    account.kind === "izly" ? "Repas Crous non notés" : account.kind === "cash" ? "Dépenses en espèces non notées" : "Ajustement de solde",
  );
  const preview = $derived.by(() => {
    if (gap === null) return null;
    if (gap === 0) return { text: "Aucun écart : le solde est déjà juste.", tone: "secondary" };
    return { text: `Écart : ${gap > 0 ? "+" : "−"}${euros(Math.abs(gap))} → enregistré comme ${gap < 0 ? "dépense" : "revenu"}`,
             tone: gap < 0 ? "" : "positive" };
  });
  const expenseCategories = $derived(store.categoriesFor("expense"));

  onMount(() => {
    note = defaultNote;
    const expenses = store.categoriesFor("expense");
    categoryID = account.kind === "izly" && expenses.some(c => c.id === "restaurants")
      ? "restaurants"
      : (expenses.find(c => c.id === "otherExpense")?.id ?? expenses[0]?.id ?? "");
    input?.focus();
  });

  function save() {
    if (parsedBalance === null || !canSave) return;
    const trimmed = note.trim();
    adjustBalance(store, account, parsedBalance, { date, categoryID, note: trimmed.length === 0 ? defaultNote : trimmed });
    onclose();
  }
</script>

<Sheet title="Ajuster le solde de {account.name}" {onclose} width={440}>
  <form class="col" style="gap: var(--padding)" onsubmit={(e) => { e.preventDefault(); save(); }}>
    <div class="caption center nums">Solde actuel dans Budget : {euros(current)}</div>

    <div class="col tight center balance">
      <span class="caption">Solde réel</span>
      <span class="row tight amount-line">
        <input bind:this={input} class="amount-input large-amount" type="text" inputmode="decimal" placeholder="0,00"
               aria-label="Solde réel" bind:value={balanceText} />
        <span class="secondary large-amount">€</span>
      </span>
    </div>

    {#if preview}<div class="center nums {preview.tone}">{preview.text}</div>{/if}

    {#if gap !== null && gap < 0}
      <Card>
        <span class="caption">Catégorie de l’écart</span>
        <div class="categories">
          {#each expenseCategories as category (category.id)}
            {@const selected = categoryID === category.id}
            <button type="button" class="category" class:selected aria-label={category.label} onclick={() => (categoryID = category.id)}>
              <span class="ring"><CategoryBadge icon={category.icon} colorIndex={category.colorIndex} /></span>
              <span class="caption truncate" class:primary={selected}>{category.label}</span>
            </button>
          {/each}
        </div>
      </Card>
    {/if}

    <Card><DateField value={date} onchange={(d) => (date = d)} label="Date" /></Card>
    <Card>
      <textarea class="note" rows="1" placeholder={defaultNote} bind:value={note} aria-label="Note"></textarea>
    </Card>
  </form>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .center { text-align: center; align-items: center; }
  .balance { padding: var(--spacing) 0; }
  .amount-line { justify-content: center; }
  .amount-input {
    width: 150px; text-align: right; border: none; outline: none; background: transparent; color: var(--text-primary);
  }
  .categories { display: flex; gap: var(--spacing); overflow-x: auto; padding: 2px; }
  .category { display: flex; flex-direction: column; align-items: center; gap: 4px; border: none; background: none; min-width: 56px; max-width: 72px; }
  .category .ring { border-radius: 50%; display: inline-flex; outline: 2px solid transparent; outline-offset: -1px; }
  .category.selected .ring { outline-color: var(--accent); }
  .category .primary { color: var(--text-primary); }
  .note {
    width: 100%; resize: none; border: none; outline: none; background: transparent; color: var(--text-primary); font: inherit;
    field-sizing: content; max-height: 6em;
  }
</style>
