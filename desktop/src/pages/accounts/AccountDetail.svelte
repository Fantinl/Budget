<script lang="ts">
  // Détail d'un compte : en-tête, mois en cours, évolution du solde et opérations (AccountDetailView.swift).
  import { navigate, store } from "../../lib/app.svelte";
  import type { Draft } from "../../lib/drafts";
  import { addMonths, startOfMonth } from "../../lib/dates";
  import { euros, monthTitle } from "../../lib/format";
  import { emptyTransaction, isTransfer, newID, resolvedAccountID, signedCents, type Transaction, MAIN_ACCOUNT_ID } from "../../lib/model";
  import { balance, transactionsOf } from "../../lib/logic/accounts";
  import { mealsRemaining } from "../../lib/logic/meals";
  import { createTransfer, deleteTransfer, transferLegs } from "../../lib/logic/transfers";
  import { categoryColor } from "../../lib/theme.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import TransactionRow from "../../ui/TransactionRow.svelte";
  import OperationEditor from "../operations/OperationEditor.svelte";
  import TransferEditor from "../operations/TransferEditor.svelte";
  import AccountCard from "./AccountCard.svelte";
  import AccountEditor from "./AccountEditor.svelte";
  import AccountShell from "./AccountShell.svelte";
  import AdjustBalanceSheet from "./AdjustBalanceSheet.svelte";
  import BalanceChart from "./BalanceChart.svelte";
  import ContextMenu, { type MenuItem } from "./ContextMenu.svelte";
  import MealPlanCard from "./MealPlanCard.svelte";

  let { accountID }: { accountID: string } = $props();

  let editing = $state(false);
  let draft = $state<Draft | null>(null);
  let search = $state("");
  let showTransfer = $state(false);
  let showAdjust = $state(false);
  let menu = $state<{ x: number; y: number; items: MenuItem[] } | null>(null);

  const account = $derived(store.account(accountID));
  const all = $derived(transactionsOf(store, account));
  const isIzly = $derived(account.kind === "izly");
  const tint = $derived(categoryColor(account.colorIndex));

  /// Comparaison sans accents ni casse (localizedStandardContains).
  const fold = (text: string) => text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

  const filtered = $derived.by(() => {
    if (search.length === 0) return all;
    const q = fold(search);
    return all.filter(t => fold(t.note).includes(q) || fold(store.categoryOf(t).label).includes(q));
  });

  /// Opérations groupées par mois, plus récent d'abord.
  const months = $derived.by(() => {
    const groups = new Map<number, Transaction[]>();
    for (const t of filtered) {
      const key = startOfMonth(t.date).getTime();
      groups.set(key, [...(groups.get(key) ?? []), t]);
    }
    return [...groups.entries()].sort((a, b) => b[0] - a[0]).map(([key, items]) => ({ month: new Date(key), items }));
  });

  const summary = $derived.by(() => {
    const start = startOfMonth(new Date()).getTime();
    const month = all.filter(t => startOfMonth(t.date).getTime() === start);
    return {
      income: month.filter(t => t.kind === "income").reduce((sum, t) => sum + t.amountCents, 0),
      expense: month.filter(t => t.kind === "expense").reduce((sum, t) => sum + t.amountCents, 0),
      transfers: month.filter(isTransfer).reduce((sum, t) => sum + signedCents(t), 0),
    };
  });

  /// Solde à la fin de chacun des 12 derniers mois (maintenant pour le mois en cours).
  const series = $derived.by(() => {
    const now = new Date();
    const current = startOfMonth(now);
    return Array.from({ length: 12 }, (_, i) => {
      const start = addMonths(current, -(11 - i));
      const end = new Date(addMonths(start, 1).getTime() - 1000);
      return { date: start, value: balance(store, account, end.getTime() < now.getTime() ? end : now) };
    });
  });

  const highlightAdjust = $derived(account.kind === "cash" || account.kind === "card");
  const transferDisabled = $derived(account.isArchived || (isIzly ? store.selectableAccounts.length === 0 : store.selectableAccounts.length < 2));

  function duplicate(t: Transaction) {
    const legs = t.transferID ? transferLegs(store, t.transferID) : null;
    if (legs) {
      createTransfer(store, resolvedAccountID(legs.out), resolvedAccountID(legs.in), legs.out.amountCents, legs.out.date, legs.out.note);
    } else {
      store.upsert({ ...t, id: newID(), recurringID: null });
    }
  }

  function remove(t: Transaction) {
    if (t.transferID) deleteTransfer(store, t.transferID); else store.delete(t);
  }

  function openMenu(e: MouseEvent, t: Transaction) {
    e.preventDefault();
    menu = { x: e.clientX, y: e.clientY, items: [
      { label: "Modifier", icon: "pencil", action: () => (draft = { transaction: t, isNew: false }) },
      { label: "Dupliquer", icon: "plus.square.on.square", action: () => duplicate(t) },
      { label: "Supprimer", icon: "trash", danger: true, action: () => remove(t) },
    ] };
  }

  function addTransaction() {
    const transaction = emptyTransaction(store.categoriesFor("expense")[0]?.id ?? "");
    if (accountID !== MAIN_ACCOUNT_ID) transaction.accountID = accountID;
    draft = { transaction, isNew: true };
  }

  function closeEditor() {
    editing = false;
    // Compte supprimé depuis l'éditeur : retour à la liste.
    if (!store.accounts.some(a => a.id === accountID)) navigate("accounts");
  }
</script>

<div class="page detail">
  <div class="row top">
    <button type="button" class="btn plain" onclick={() => navigate("accounts")}><Icon name="chevron.left" size={14} /> Comptes</button>
    <span class="title truncate">{account.name}</span>
  </div>

  <AccountShell {account}>
    <div class="col header">
      <AccountCard {account} large />
      {#if isIzly}
        <div class="title secondary">≈ {mealsRemaining(store, account)} repas restants</div>
        <div class="caption tertiary hint">Recopie le solde affiché dans l’app Izly pour enregistrer les repas non notés.</div>
      {/if}
      <div class="buttons caption" style:--tint={tint}>
        <button type="button" class="btn small" class:tinted={highlightAdjust} disabled={account.isArchived} onclick={() => (showAdjust = true)}>
          <Icon name="equal.circle" size={13} /> Ajuster le solde
        </button>
        {#if isIzly}
          <button type="button" class="btn small tinted" disabled={transferDisabled} onclick={() => (showTransfer = true)}>
            <Icon name="plus.circle.fill" size={13} /> Recharger
          </button>
        {:else}
          <button type="button" class="btn small" disabled={transferDisabled} onclick={() => (showTransfer = true)}>
            <Icon name="arrow.left.arrow.right" size={13} /> Virement
          </button>
        {/if}
        <button type="button" class="btn small" onclick={() => (editing = true)}><Icon name="pencil" size={13} /> Modifier</button>
      </div>
    </div>
  </AccountShell>

  {#if isIzly}<MealPlanCard accountID={accountID} />{/if}

  <Card>
    <span class="title">Ce mois-ci</span>
    <div class="row stats">
      <div class="col tight stat"><span class="caption">Entrées</span><span class="amount positive big">{euros(summary.income)}</span></div>
      <div class="col tight stat"><span class="caption">Sorties</span><span class="amount big">{euros(summary.expense)}</span></div>
    </div>
    {#if summary.transfers !== 0}
      <span class="caption nums">dont virements : {summary.transfers > 0 ? "+" : ""}{euros(summary.transfers)}</span>
    {/if}
  </Card>

  <Card>
    <span class="title">Évolution du solde</span>
    <BalanceChart points={series} {tint} />
  </Card>

  <div class="search">
    <Icon name="magnifyingglass" size={13} color="var(--text-tertiary)" />
    <input type="text" placeholder="Rechercher dans les opérations" bind:value={search} />
    {#if search.length > 0}
      <button type="button" class="clear" aria-label="Effacer" onclick={() => (search = "")}><Icon name="xmark.circle.fill" size={13} color="var(--text-tertiary)" /></button>
    {/if}
  </div>

  {#if months.length === 0}
    <div class="empty col" style="align-items: center">
      <Icon name={search.length === 0 ? "tray" : "magnifyingglass"} size={32} />
      <span class="title secondary">{search.length === 0 ? "Aucune opération" : "Aucun résultat"}</span>
    </div>
  {/if}

  {#each months as group (group.month.getTime())}
    <div class="col tight">
      <span class="caption month">{monthTitle(group.month)}</span>
      <Card padded={false}>
        <div class="list">
        {#each group.items as t, index (t.id)}
          {#if index > 0}<hr class="separator inset" />{/if}
          <button type="button" class="row-button" onclick={() => (draft = { transaction: t, isNew: false })}
                  oncontextmenu={(e) => openMenu(e, t)}>
            <TransactionRow transaction={t} />
          </button>
        {/each}
        </div>
      </Card>
    </div>
  {/each}

  <button type="button" class="fab" onclick={addTransaction}><Icon name="plus" size={15} /> Ajouter</button>
</div>

{#if menu}<ContextMenu x={menu.x} y={menu.y} items={menu.items} onclose={() => (menu = null)} />{/if}
{#if editing}<AccountEditor {account} onclose={closeEditor} />{/if}
{#if draft}<OperationEditor {draft} onclose={() => (draft = null)} />{/if}
{#if showTransfer}
  <TransferEditor transferID={null} lockedToID={isIzly ? accountID : null} fromAccountID={isIzly ? null : accountID}
                  onclose={() => (showTransfer = false)} />
{/if}
{#if showAdjust}<AdjustBalanceSheet {account} onclose={() => (showAdjust = false)} />{/if}

<style>
  .detail { padding-bottom: 72px; }
  .top { gap: 8px; }
  .header { gap: var(--spacing); align-items: stretch; }
  .hint { text-align: right; }
  .buttons { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: var(--spacing); }
  .btn.tinted { background: var(--tint); border-color: transparent; color: var(--on-accent); }
  .btn.tinted:hover:not(:disabled) { background: var(--tint); filter: brightness(1.08); }
  .stats { gap: var(--spacing); }
  .stat { flex: 1; }
  .big { font-size: var(--title); }
  .search {
    display: flex; align-items: center; gap: 6px; padding: 6px 10px; border-radius: var(--radius-small);
    background: var(--surface-secondary); font-size: var(--caption);
  }
  .search input { flex: 1; min-width: 0; border: none; outline: none; background: transparent; }
  .clear { border: none; background: none; padding: 0; display: inline-flex; }
  .list { display: flex; flex-direction: column; }
  .month { padding-left: calc(var(--spacing) / 2); }
  .row-button {
    display: block; width: 100%; border: none; background: transparent; color: inherit; text-align: left;
    padding: var(--spacing) var(--padding);
  }
  .row-button:hover { background: var(--surface-secondary); }
  .separator.inset { margin-left: calc(var(--padding) + var(--icon-size) + var(--spacing)); }
  .fab {
    position: sticky; bottom: var(--padding); align-self: flex-end; display: inline-flex; align-items: center; gap: 6px;
    padding: var(--spacing) calc(var(--padding) + 4px); border: none; border-radius: 999px;
    background: var(--accent); color: var(--on-accent); font-size: var(--title); font-weight: var(--title-weight);
    box-shadow: 0 4px 10px color-mix(in srgb, var(--accent) 35%, transparent);
  }
  .fab:hover { filter: brightness(1.08); }
</style>
