<script lang="ts">
  // Page Opérations : sélecteur de mois, recherche, filtres, saisie express, ajouts rapides, résumé du mois,
  // liste groupée par jour, sélection multiple et clavier. Port de ContentView.swift (+ ShortcutCommands.swift).
  // `accountID` : vue d'un compte (utilisée par le détail d'un compte) ; null = tous les comptes.
  import { Inbox, Search } from "@lucide/svelte";
  import { type Account, type Category, type Transaction, emptyTransaction, isTransfer, MAIN_ACCOUNT_ID, accountKinds } from "../../lib/model";
  import type { Draft } from "../../lib/drafts";
  import { store } from "../../lib/app.svelte";
  import { nav } from "../../lib/app.svelte";
  import { addMonths, isInMonth, startOfDay, startOfMonth } from "../../lib/dates";
  import { euros } from "../../lib/format";
  import { balance } from "../../lib/logic/accounts";
  import { copyOf, deleteTransactions, duplicateTransactions, updateTransactions } from "../../lib/logic/bulk";
  import {
    emptyFilter, isFilterActive, isHiddenFromOperations, izlySpending, matches, matchesSearch, type OperationFilter,
  } from "../../lib/logic/filter";
  import { confirmDialog } from "../../lib/platform";
  import { BudgetStore } from "../../lib/store.svelte";
  import { currentTheme } from "../../lib/theme.svelte";
  import AccountBadge from "../../ui/AccountBadge.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import MonthPicker from "../../ui/MonthPicker.svelte";
  import { monthStartsWithData } from "../../lib/logic/stats";
  import TransactionRow from "../../ui/TransactionRow.svelte";
  import BulkEditSheet from "./BulkEditSheet.svelte";
  import ExpressEntryBar from "./ExpressEntryBar.svelte";
  import FilterChips from "./FilterChips.svelte";
  import FilterForm from "./FilterForm.svelte";
  import MonthSummary from "./MonthSummary.svelte";
  import OperationEditor from "./OperationEditor.svelte";
  import PopupMenu, { type MenuItem } from "./PopupMenu.svelte";
  import QuickAddBar, { type QuickAddToast } from "./QuickAddBar.svelte";
  import QuickAddToastView from "./QuickAddToast.svelte";
  import SelectionActionBar from "./SelectionActionBar.svelte";
  import { hasMod, isEditing, modalOpen, shortcutLabel } from "./keys";

  let { accountID = null }: { accountID?: string | null } = $props();

  let month = $state(startOfMonth(new Date()));
  let draft = $state.raw<Draft | null>(null);
  let search = $state("");
  let toast = $state.raw<QuickAddToast | null>(null);
  let filter = $state.raw<OperationFilter>(emptyFilter());
  let showFilters = $state(false);
  let selection = $state.raw(new Set<string>());
  /// Dernière ligne cliquée (point de départ des plages ⇧-clic).
  let anchor = $state<string | null>(null);
  let showBulkEdit = $state(false);
  let menu = $state<{ x: number; y: number; items: MenuItem[] } | null>(null);
  let expressBar = $state<{ focus: () => void }>();
  let searchInput = $state<HTMLInputElement>();
  let filterWrap = $state<HTMLDivElement>();

  /// Mois ayant des opérations (pastille dans le menu des mois).
  const monthsWithData = $derived(monthStartsWithData(store.transactions));

  const currentAccount = $derived(accountID ? store.accounts.find(a => a.id === accountID) ?? null : null);

  const accountBalance = $derived(currentAccount ? balance(store, currentAccount) : 0);

  /// Opérations du mois (du compte affiché s'il y en a un), Izly comprises : sert au résumé du mois.
  const monthTransactions = $derived.by(() => {
    const all = store.transactionsInMonthOf(month);
    return accountID ? all.filter(t => (t.accountID ?? MAIN_ACCOUNT_ID) === accountID) : all;
  });

  /// Opérations listées : sans les opérations Izly, sauf dans la vue d'un compte.
  const listedTransactions = $derived(accountID === null ? monthTransactions.filter(t => !isHiddenFromOperations(store, t)) : monthTransactions);

  const hasActiveFilterOrSearch = $derived(isFilterActive(filter) || search.length > 0);

  /// Ligne récapitulative Izly du mois (vue « tous comptes », sans recherche ni filtre).
  const izlySummary = $derived.by(() => {
    if (accountID !== null || hasActiveFilterOrSearch) return null;
    const summary = izlySpending(store, monthTransactions);
    return summary.count > 0 ? summary : null;
  });

  const filteredTransactions = $derived.by(() => {
    let result = listedTransactions;
    if (isFilterActive(filter)) result = result.filter(t => matches(filter, t));
    if (search.length === 0) return result;
    return result.filter(t => matchesSearch(store, t, search));
  });

  /// Transactions regroupées par jour, du plus récent au plus ancien.
  const days = $derived.by(() => {
    const groups = new Map<number, { day: Date; items: Transaction[] }>();
    for (const t of filteredTransactions) {
      const day = startOfDay(t.date);
      const group = groups.get(day.getTime());
      if (group) group.items.push(t);
      else groups.set(day.getTime(), { day, items: [t] });
    }
    return [...groups.values()].sort((a, b) => b.day.getTime() - a.day.getTime());
  });

  /// Ordre d'affichage (pour les plages et « tout sélectionner »).
  const displayedIDs = $derived(days.flatMap(g => g.items.map(t => t.id)));
  const selectedTransactions = $derived(filteredTransactions.filter(t => selection.has(t.id)));
  const showAccounts = $derived(store.activeAccounts.length > 1 && accountID === null);
  const canGoNext = $derived(addMonths(month, 1).getTime() <= startOfMonth(new Date()).getTime());

  // Une ligne qui disparaît (mois, filtre, suppression) quitte la sélection.
  $effect(() => {
    const ids = new Set(displayedIDs);
    const valid = [...selection].filter(id => ids.has(id));
    if (valid.length !== selection.size) selection = new Set(valid);
  });

  const dayFormat = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" });
  /// « Vendredi 30 Octobre » (chaque mot commence par une majuscule, comme `.capitalized`).
  const dayTitle = (d: Date) => dayFormat.format(d).split(" ").map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" ");

  // MARK: - Sélection

  function handleTap(e: MouseEvent, transaction: Transaction) {
    if (e.shiftKey && anchor) {
      const from = displayedIDs.indexOf(anchor);
      const to = displayedIDs.indexOf(transaction.id);
      if (from >= 0 && to >= 0) {
        selection = new Set(displayedIDs.slice(Math.min(from, to), Math.max(from, to) + 1));
        return;
      }
    }
    if (hasMod(e) || e.shiftKey) { toggle(transaction.id); return; }
    if (selection.size > 0) { clearSelection(); return; }
    draft = { transaction, isNew: false };
  }

  function toggle(id: string) {
    const next = new Set(selection);
    if (!next.delete(id)) next.add(id);
    selection = next;
    anchor = id;
  }

  function clearSelection() {
    selection = new Set();
    anchor = null;
  }

  async function requestDelete() {
    if (selection.size === 0) return;
    const count = selection.size;
    const ok = await confirmDialog("Les virements sont supprimés avec leur opération jumelle.", {
      title: `Supprimer ${count} opération${count > 1 ? "s" : ""} ?`, okLabel: "Supprimer" });
    if (!ok) return;
    deleteTransactions(store, selection);
    clearSelection();
  }

  function applyCategory(category: Category) {
    const ids = new Set(selectedTransactions.filter(t => !isTransfer(t) && t.kind === category.kind).map(t => t.id));
    updateTransactions(store, ids, t => ({ ...t, categoryID: category.id }));
  }

  function applyAccount(account: Account) {
    const stored = BudgetStore.storedAccountID(account.id);
    updateTransactions(store, selection, t => ({ ...t, accountID: stored }));
  }

  function duplicateSelection() {
    duplicateTransactions(store, selection);
    clearSelection();
  }

  function rowMenu(e: MouseEvent, transaction: Transaction) {
    e.preventDefault();
    const items: MenuItem[] = [{ label: "Modifier", icon: "pencil", onclick: () => (draft = { transaction, isNew: false }) }];
    if (!isTransfer(transaction)) {
      // Même date que l'original
      items.push({ label: "Dupliquer", icon: "plus.square.on.square", onclick: () => (draft = { transaction: copyOf(transaction), isNew: true }) });
    }
    items.push({ label: "Supprimer", icon: "trash", danger: true, onclick: () => deleteTransactions(store, new Set([transaction.id])) });
    menu = { x: e.clientX, y: e.clientY, items };
  }

  // MARK: - Nouvelle opération et clavier

  /// Nouvelle opération vide (mois et compte de la vue).
  function startNewOperation() {
    const transaction = emptyTransaction(store.categoriesFor("expense")[0]?.id ?? "");
    // Si on regarde un autre mois, on pré-remplit une date dans ce mois-là.
    if (!isInMonth(month, new Date())) transaction.date = month;
    // Compte de la vue s'il y en a un, sinon le compte par défaut (réglages).
    transaction.accountID = store.accountIDForNewTransaction(accountID);
    draft = { transaction, isNew: true };
  }

  function onkeydown(e: KeyboardEvent) {
    if (modalOpen() || nav.settingsOpen) return;
    const key = e.key.toLowerCase();
    if (hasMod(e) && !e.altKey) {
      if (key === "n") { e.preventDefault(); startNewOperation(); }
      else if (key === "e") { e.preventDefault(); expressBar?.focus(); }
      else if (key === "f") { e.preventDefault(); searchInput?.focus(); searchInput?.select(); }
      else if (key === "arrowleft") { e.preventDefault(); month = addMonths(month, -1); }
      else if (key === "arrowright") { e.preventDefault(); if (canGoNext) month = addMonths(month, 1); }
      else if (key === "a" && !isEditing()) { e.preventDefault(); selection = new Set(displayedIDs); }
      return;
    }
    if (isEditing() || hasMod(e)) return;
    if (key === "escape" && selection.size > 0) { e.preventDefault(); clearSelection(); }
    else if ((key === "delete" || key === "backspace") && selection.size > 0) { e.preventDefault(); void requestDelete(); }
  }

  function onsearchkey(e: KeyboardEvent) {
    if (e.key === "Escape") { search = ""; searchInput?.blur(); }
  }

  // Popover des filtres : se ferme au clic extérieur ou sur Échap.
  function onwindowdown(e: MouseEvent) {
    if (showFilters && filterWrap && !filterWrap.contains(e.target as Node)) showFilters = false;
  }
  function onfilterkey(e: KeyboardEvent) {
    if (showFilters && e.key === "Escape") { showFilters = false; e.stopPropagation(); }
  }
</script>

<svelte:window {onkeydown} onmousedown={onwindowdown} />

{#snippet row(transaction: Transaction)}
  {@const selected = selection.has(transaction.id)}
  <div class="op-row" class:selected role="button" tabindex="0"
       onclick={(e) => handleTap(e, transaction)}
       onkeydown={(e) => { if ((e.key === "Enter" || e.key === " ") && e.target === e.currentTarget) { e.preventDefault(); draft = { transaction, isNew: false }; } }}
       oncontextmenu={(e) => rowMenu(e, transaction)}>
    {#if selected}<span class="check"><Icon name="checkmark.circle.fill" size={18} color="var(--accent)" /></span>{/if}
    <TransactionRow {transaction} showAccount={showAccounts} />
  </div>
{/snippet}

<div class="ops-root">
  <div class="page">
    <div class="toolbar">
      <span class="spacer"></span>
      <div class="filter-wrap" bind:this={filterWrap} onkeydowncapture={onfilterkey} role="presentation">
        <button type="button" class="btn icon plain" class:active={isFilterActive(filter)} title="Filtrer les opérations"
                aria-label="Filtrer les opérations" onclick={() => (showFilters = !showFilters)}>
          <Icon name="line.3.horizontal.decrease.circle" size={18} color={isFilterActive(filter) ? "var(--accent)" : "currentColor"} />
        </button>
        {#if showFilters}
          <div class="popover"><FilterForm bind:filter showAccount={accountID === null} /></div>
        {/if}
      </div>
      <div class="search caption" title={`Rechercher (${shortcutLabel("F")})`}>
        <Icon name="magnifyingglass" size={13} color="var(--text-tertiary)" />
        <input bind:this={searchInput} bind:value={search} type="text" placeholder="Rechercher" aria-label="Rechercher" onkeydown={onsearchkey} />
        {#if search.length > 0}
          <button type="button" class="clear" title="Effacer" aria-label="Effacer" onclick={() => (search = "")}>
            <Icon name="xmark.circle.fill" size={13} color="var(--text-tertiary)" />
          </button>
        {/if}
      </div>
    </div>

    <!-- En-tête : compte, mois, filtres, saisie express, ajouts rapides, résumé et ligne Izly -->
    {#if currentAccount}
      <div class="account-header">
        <AccountBadge account={currentAccount} size={44} />
        <div class="col tight names">
          <span class="title">{currentAccount.name}</span>
          <span class="caption tertiary">{accountKinds[currentAccount.kind].label}</span>
        </div>
        <span class="spacer"></span>
        <div class="col tight right">
          <span class="large-amount" class:negative={accountBalance < 0}>{euros(accountBalance)}</span>
          <span class="caption tertiary">Solde actuel</span>
        </div>
      </div>
    {/if}

    <div class="month-picker"><MonthPicker bind:month monthsWithData={monthsWithData} /></div>
    <FilterChips bind:filter />
    <ExpressEntryBar bind:this={expressBar} {accountID} onOpenForm={(t) => (draft = { transaction: t, isNew: true })} />
    <QuickAddBar bind:month bind:draft bind:toast {accountID} />
    <MonthSummary transactions={monthTransactions} {month} />
    {#if izlySummary}
      {@const izly = store.accounts.find(a => a.kind === "izly")}
      <Card>
        <div class="row">
          {#if izly}<AccountBadge account={izly} size={currentTheme().iconSize} />{/if}
          <span class="nums">Izly : {izlySummary.count} repas · {euros(izlySummary.totalCents)}</span>
          <span class="spacer"></span>
          <span class="caption tertiary">Détail dans le compte</span>
        </div>
      </Card>
    {/if}

    {#if days.length === 0 && !izlySummary}
      <div class="empty-state">
        {#if hasActiveFilterOrSearch}<Search size={40} strokeWidth={1.5} aria-hidden="true" />{:else}<Inbox size={40} strokeWidth={1.5} aria-hidden="true" />{/if}
        <span class="empty-title">{hasActiveFilterOrSearch ? "Aucun résultat" : "Aucune opération ce mois-ci"}</span>
        {#if !hasActiveFilterOrSearch}<span class="caption">Ajoute une dépense avec le bouton « Ajouter ».</span>{/if}
      </div>
    {/if}

    {#each days as group (group.day.getTime())}
      <div class="day-group">
        <span class="caption day-title">{dayTitle(group.day)}</span>
        <Card padded={false}>
          {#each group.items as transaction, index (transaction.id)}
            {#if index > 0}<hr class="separator inset" />{/if}
            {@render row(transaction)}
          {/each}
        </Card>
      </div>
    {/each}
  </div>

  <!-- Bas de l'écran : bandeau d'ajout rapide, bouton « Ajouter » ou barre d'actions de la sélection -->
  <div class="bottom">
    <div class="bottom-inner">
      {#if toast}
        {#key toast.id}
          <div class="toast-slot"><QuickAddToastView {toast} ondismiss={() => (toast = null)} /></div>
        {/key}
      {/if}
      {#if selection.size === 0}
        <div class="add-row">
          <button type="button" class="add" title={`Nouvelle opération (${shortcutLabel("N")})`} onclick={startNewOperation}>
            <Icon name="plus" size={16} />Ajouter
          </button>
        </div>
      {:else}
        <SelectionActionBar selected={selectedTransactions} oncategory={applyCategory} onaccount={applyAccount}
                            onedit={() => (showBulkEdit = true)} onduplicate={duplicateSelection} ondelete={requestDelete}
                            onclose={clearSelection} />
      {/if}
    </div>
  </div>
</div>

{#if menu}
  <PopupMenu x={menu.x} y={menu.y} items={menu.items} onclose={() => (menu = null)} />
{/if}

{#if showBulkEdit}
  <BulkEditSheet transactions={selectedTransactions} onclose={() => (showBulkEdit = false)} />
{/if}

{#if draft}
  {#key draft.transaction.id}
    <OperationEditor {draft} onclose={() => (draft = null)} />
  {/key}
{/if}

<style>
  .ops-root { min-height: 100%; display: flex; flex-direction: column; }
  .ops-root > .page { flex: 1; width: 100%; }
  .toolbar { display: flex; align-items: center; gap: 8px; }
  .filter-wrap { position: relative; }
  .popover {
    position: absolute; right: 0; top: calc(100% + 6px); z-index: 50; width: 340px; max-height: 460px; overflow-y: auto;
    background: var(--background); border-radius: var(--radius-small); box-shadow: 0 8px 30px rgba(0, 0, 0, 0.22), 0 0 0 1px var(--separator);
  }
  .search {
    display: flex; align-items: center; gap: 4px; width: 150px; height: 28px; padding: 0 8px;
    border-radius: var(--radius-small); background: var(--surface-secondary); border: 1px solid var(--separator);
  }
  .search input { flex: 1; min-width: 0; border: none; outline: none; background: transparent; padding: 0; font-size: var(--caption); }
  .search:focus-within { border-color: var(--accent); }
  .clear { border: none; background: transparent; padding: 0; display: inline-flex; }
  .account-header { display: flex; align-items: center; gap: var(--spacing); }
  .names { align-items: flex-start; }
  .right { align-items: flex-end; }
  .month-picker { display: flex; justify-content: center; }
  .empty-state {
    display: flex; flex-direction: column; align-items: center; gap: 8px; padding-top: var(--padding);
    color: var(--text-secondary); text-align: center;
  }
  .empty-title { font-size: 16px; font-weight: 600; }
  .day-group { display: flex; flex-direction: column; gap: 6px; }
  .day-title { padding-left: 6px; }
  .op-row {
    display: flex; align-items: center; gap: var(--spacing); padding: var(--spacing) var(--padding);
    border-radius: calc(var(--radius) / 2); cursor: default; outline: none;
  }
  .op-row:hover { background: color-mix(in srgb, var(--text-primary) 4%, transparent); }
  .op-row.selected { background: color-mix(in srgb, var(--accent) 12%, transparent); }
  .op-row:focus-visible { box-shadow: inset 0 0 0 2px color-mix(in srgb, var(--accent) 50%, transparent); }
  .check { display: inline-flex; flex-shrink: 0; }
  .separator.inset { margin-left: calc(var(--padding) + var(--icon-size) + var(--spacing)); }
  .bottom { position: sticky; bottom: 0; z-index: 20; pointer-events: none; padding: 0 var(--padding) var(--padding); }
  .bottom-inner {
    max-width: 1000px; margin: 0 auto; display: flex; flex-direction: column; gap: var(--spacing); align-items: stretch;
  }
  .bottom-inner > :global(*) { pointer-events: auto; }
  .toast-slot { display: flex; justify-content: center; pointer-events: none; }
  .toast-slot > :global(*) { pointer-events: auto; }
  .add-row { display: flex; justify-content: flex-end; pointer-events: none; }
  .add {
    pointer-events: auto; display: inline-flex; align-items: center; gap: 6px; border: none; cursor: default;
    font-size: var(--title); font-weight: var(--title-weight); color: var(--on-accent); background: var(--accent);
    padding: var(--spacing) calc(var(--padding) + 4px); border-radius: 999px;
    box-shadow: 0 4px 10px color-mix(in srgb, var(--accent) 35%, transparent);
  }
  .add:hover { filter: brightness(1.08); }
</style>
