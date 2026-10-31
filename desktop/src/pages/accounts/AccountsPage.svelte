<script lang="ts">
  // Page « Comptes » : patrimoine, répartition, puis cartes de comptes par type ou par banque (AccountsView.swift).
  // Avec `nav.accountID`, affiche le détail d'un compte (AccountDetailView.swift).
  import { onMount } from "svelte";
  import { nav, navigate, store } from "../../lib/app.svelte";
  import { euros } from "../../lib/format";
  import { type Account, type AccountFamily, bankLabel, families, familyLabel, familyOf, MAIN_ACCOUNT_ID } from "../../lib/model";
  import { archiveAccount, totalBalance, unarchiveAccount, value as valueOf } from "../../lib/logic/accounts";
  import { refreshRates } from "../../lib/logic/rates";
  import { prefs } from "../../lib/prefs.svelte";
  import { categoryColor } from "../../lib/theme.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import TransferEditor from "../operations/TransferEditor.svelte";
  import AccountCard from "./AccountCard.svelte";
  import AccountDetail from "./AccountDetail.svelte";
  import AccountEditor from "./AccountEditor.svelte";
  import AccountShell from "./AccountShell.svelte";
  import AdjustBalanceSheet from "./AdjustBalanceSheet.svelte";
  import ContextMenu, { type MenuItem } from "./ContextMenu.svelte";
  import { requestAccountDeletion } from "./accountDeletion";

  interface Section { id: string; title: string; accounts: Account[] }
  interface TransferRequest { fromAccountID: string | null; toAccountID: string | null }

  let editing = $state<{ account: Account | null } | null>(null);
  let transfer = $state<TransferRequest | null>(null);
  let adjusting = $state<Account | null>(null);
  let showArchived = $state(false);
  let menu = $state<{ x: number; y: number; items: MenuItem[] } | null>(null);

  onMount(() => { void refreshRates(store); });

  const mode = $derived(prefs.accountsGrouping.value === "bank" ? "bank" : "family");
  const active = $derived(store.activeAccounts);
  const archived = $derived(store.accounts.filter(a => a.isArchived));

  const sections = $derived.by((): Section[] => {
    if (mode === "family") {
      return families.flatMap((family): Section[] => {
        const list = active.filter(a => familyOf(a.kind) === family);
        return list.length === 0 ? [] : [{ id: family, title: familyLabel[family], accounts: list }];
      });
    }
    const groups = new Map<string, Account[]>();
    for (const a of active) groups.set(bankLabel(a), [...(groups.get(bankLabel(a)) ?? []), a]);
    const noBank = "Sans banque";
    return [...groups.keys()]
      .sort((a, b) => {
        if (a === noBank) return 1;
        if (b === noBank) return -1;
        return a.localeCompare(b, "fr", { numeric: true, sensitivity: "base" });
      })
      .map(title => ({ id: title, title, accounts: groups.get(title) ?? [] }));
  });

  const total = $derived(totalBalance(store));
  const familyTotals = $derived(
    families.flatMap((family): { family: AccountFamily; cents: number }[] => {
      const list = active.filter(a => familyOf(a.kind) === family);
      return list.length === 0 ? [] : [{ family, cents: list.reduce((sum, a) => sum + valueOf(store, a), 0) }];
    }),
  );
  const positiveSum = $derived(familyTotals.reduce((sum, f) => sum + Math.max(f.cents, 0), 0));
  const familyColor = (family: AccountFamily) => categoryColor((families.indexOf(family) * 2) % 12);

  const canTransfer = $derived(store.selectableAccounts.length >= 2);

  function openMenu(e: MouseEvent, account: Account) {
    e.preventDefault();
    e.stopPropagation();
    const items: MenuItem[] = [{ label: "Modifier…", icon: "pencil", action: () => (editing = { account }) }];
    if (!account.isArchived) items.push({ label: "Ajuster le solde…", icon: "equal.circle", action: () => (adjusting = account) });
    if (!account.isArchived && account.kind === "izly" && store.selectableAccounts.length > 0) {
      items.push({ label: "Recharger…", icon: "plus.circle", action: () => (transfer = { fromAccountID: null, toAccountID: account.id }) });
    } else if (!account.isArchived && account.kind !== "izly" && store.selectableAccounts.length > 1) {
      items.push({ label: "Virement depuis ce compte…", icon: "arrow.left.arrow.right",
                  action: () => (transfer = { fromAccountID: account.id, toAccountID: null }) });
    }
    if (account.id !== MAIN_ACCOUNT_ID) {
      items.push({ label: account.isArchived ? "Désarchiver" : "Archiver", icon: "archivebox",
                   action: () => (account.isArchived ? unarchiveAccount(store, account) : archiveAccount(store, account)) });
      items.push({ label: "Supprimer…", icon: "trash", danger: true, action: () => { void requestAccountDeletion(store, account); } });
    }
    menu = { x: e.clientX, y: e.clientY, items };
  }

  function menuFromButton(e: MouseEvent, account: Account) {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    openMenu(new MouseEvent("contextmenu", { clientX: r.left, clientY: r.bottom + 4 }), account);
  }
</script>

{#snippet cardView(account: Account, isArchived: boolean)}
  <div class="cell">
    <button type="button" class="open" oncontextmenu={(e) => openMenu(e, account)}
            onclick={() => navigate("accounts", { accountID: account.id })}>
      <AccountShell {account} archived={isArchived}><AccountCard {account} /></AccountShell>
    </button>
    <button type="button" class="more" title="Actions" aria-label="Actions du compte {account.name}" onclick={(e) => menuFromButton(e, account)}>
      <Icon name="ellipsis" size={14} />
    </button>
  </div>
{/snippet}

{#if nav.accountID}
  <AccountDetail accountID={nav.accountID} />
{:else}
  <div class="page">
    <h1 class="heading">Comptes</h1>

    <Card hero>
      <div class="col">
        <span class="caption hero-secondary">Patrimoine total</span>
        <span class="large-amount">{euros(total)}</span>
        {#if positiveSum > 0}
          <div class="bar">
            {#each familyTotals as f (f.family)}
              {#if f.cents > 0}<div class="seg" style:flex="{f.cents / positiveSum} 1 0" style:background={familyColor(f.family)}></div>{/if}
            {/each}
          </div>
        {/if}
        <div class="legend">
          {#each familyTotals as f (f.family)}
            <div class="row tight">
              <span class="dot" style:background={familyColor(f.family)}></span>
              <div class="col" style="gap: 0">
                <span class="caption hero-secondary">{familyLabel[f.family]}</span>
                <span class="caption nums">{euros(f.cents)}</span>
              </div>
            </div>
          {/each}
        </div>
      </div>
    </Card>

    <div class="segmented grouping" role="group" aria-label="Regrouper par">
      <button type="button" class:selected={mode === "family"} onclick={() => (prefs.accountsGrouping.value = "family")}>Type</button>
      <button type="button" class:selected={mode === "bank"} onclick={() => (prefs.accountsGrouping.value = "bank")}>Banque</button>
    </div>

    {#each sections as section (section.id)}
      {@const subtotal = section.accounts.reduce((sum, a) => sum + valueOf(store, a), 0)}
      <section class="col">
        <div class="line">
          <div class="row" style="align-items: baseline">
            <span class="title">{section.title}</span>
            {#if mode === "bank"}
              <span class="caption tertiary">{section.accounts.length} {section.accounts.length === 1 ? "compte" : "comptes"}</span>
            {/if}
          </div>
          <span class="nums" class:negative={subtotal < 0} class:secondary={subtotal >= 0}>{euros(subtotal)}</span>
        </div>
        <div class="cards">
          {#each section.accounts as account (account.id)}{@render cardView(account, false)}{/each}
        </div>
      </section>
    {/each}

    <div class="col tight">
      <div class="actions">
        <button type="button" class="action add" onclick={() => (editing = { account: null })}>
          <Icon name="plus.circle.fill" size={15} /> Ajouter un compte
        </button>
        <button type="button" class="action transfer" disabled={!canTransfer} onclick={() => (transfer = { fromAccountID: null, toAccountID: null })}
                title={canTransfer ? "Virement entre deux comptes" : "Il faut au moins deux comptes actifs"}>
          <Icon name="arrow.left.arrow.right" size={15} /> Virement
        </button>
      </div>
      {#if !canTransfer}
        <span class="caption tertiary">Il faut au moins deux comptes actifs pour faire un virement.</span>
      {/if}
    </div>

    {#if archived.length > 0}
      <div class="col">
        <button type="button" class="disclosure caption secondary" onclick={() => (showArchived = !showArchived)} aria-expanded={showArchived}>
          <Icon name={showArchived ? "chevron.down" : "chevron.right"} size={11} /> Archivés ({archived.length})
        </button>
        {#if showArchived}
          <div class="cards">
            {#each archived as account (account.id)}{@render cardView(account, true)}{/each}
          </div>
        {/if}
      </div>
    {/if}
  </div>
{/if}

{#if menu}<ContextMenu x={menu.x} y={menu.y} items={menu.items} onclose={() => (menu = null)} />{/if}
{#if editing}<AccountEditor account={editing.account} onclose={() => (editing = null)} />{/if}
{#if transfer}
  <TransferEditor transferID={null} lockedToID={transfer.toAccountID} fromAccountID={transfer.fromAccountID} onclose={() => (transfer = null)} />
{/if}
{#if adjusting}<AdjustBalanceSheet account={adjusting} onclose={() => (adjusting = null)} />{/if}

<style>
  .heading { margin: 0; font-size: 20px; font-weight: var(--title-weight); color: var(--text-primary); }
  .hero-secondary { color: var(--hero-text-secondary); }
  .bar { display: flex; gap: 2px; height: 8px; border-radius: 4px; overflow: hidden; }
  .seg { min-width: 4px; border-radius: 4px; }
  .legend { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 6px; }
  .dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .grouping { align-self: flex-start; }
  .grouping button { min-width: 80px; }
  .cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 12px; align-items: start; }
  .cell { position: relative; min-width: 0; }
  .open { display: block; width: 100%; padding: 0; border: none; background: none; text-align: left; color: inherit; font: inherit; border-radius: var(--radius); }
  .open:hover { filter: brightness(0.985); }
  .more {
    position: absolute; top: 10px; right: 8px; width: 24px; height: 24px; display: inline-flex; align-items: center; justify-content: center;
    border: none; border-radius: 50%; background: transparent; color: var(--text-secondary); opacity: 0;
  }
  .cell:hover .more, .more:focus-visible { opacity: 1; }
  .more:hover { background: var(--surface-secondary); }
  .actions { display: flex; gap: 12px; }
  .action {
    flex: 1; min-height: 56px; display: inline-flex; align-items: center; justify-content: center; gap: 8px;
    border-radius: var(--radius); font-size: var(--body);
  }
  .add { background: transparent; color: var(--accent); border: 1.5px dashed var(--separator); }
  .transfer { background: var(--accent); color: var(--on-accent); border: none; }
  .transfer:disabled { opacity: 0.4; }
  .disclosure { display: inline-flex; align-items: center; gap: 4px; align-self: flex-start; border: none; background: none; padding: 0; }
</style>
