<script lang="ts">
  // Création (transferID null) ou modification d'un virement entre comptes. Port de TransferEditorView.swift.
  import { untrack } from "svelte";
  import { type Account, accountKinds, resolvedAccountID } from "../../lib/model";
  import { store } from "../../lib/app.svelte";
  import { amountInput, euros, parseAmount } from "../../lib/format";
  import { balance } from "../../lib/logic/accounts";
  import { createTransfer, DEFAULT_TRANSFER_NOTE, deleteTransfer, transferLegs, updateTransfer } from "../../lib/logic/transfers";
  import { confirmDialog } from "../../lib/platform";
  import Sheet from "../../ui/Sheet.svelte";
  import Card from "../../ui/Card.svelte";
  import AccountBadge from "../../ui/AccountBadge.svelte";
  import DateField from "../../ui/DateField.svelte";
  import Icon from "../../ui/Icon.svelte";
  import AmountField from "./AmountField.svelte";

  let { transferID, lockedToID = null, fromAccountID = null, onclose }: {
    transferID: string | null;
    /// Destination imposée (recharge Izly) : seule la source reste modifiable.
    lockedToID?: string | null;
    /// Compte source proposé à la création.
    fromAccountID?: string | null;
    onclose: () => void;
  } = $props();

  const transferKey = untrack(() => transferID);
  const isNew = transferKey === null;
  const legs = transferKey ? transferLegs(store, transferKey) : null;

  // Chargement initial (load() de la version Swift).
  function initial() {
    if (legs) {
      return { from: resolvedAccountID(legs.out), to: resolvedAccountID(legs.in), amount: amountInput(legs.out.amountCents),
               date: legs.out.date, note: legs.out.note === DEFAULT_TRANSFER_NOTE ? "" : legs.out.note };
    }
    const accounts = store.selectableAccounts;
    let from = fromAccountID ?? "";
    if (from === "" || !accounts.some(a => a.id === from)) from = store.defaultAccount.id;
    let to: string;
    if (lockedToID) {
      to = lockedToID;
      if (from === lockedToID) from = accounts[0]?.id ?? "";
    } else {
      to = accounts.find(a => a.id !== from)?.id ?? "";
    }
    return { from, to, amount: "", date: new Date(), note: "" };
  }
  const start = initial();
  let fromID = $state(start.from);
  let toID = $state(start.to);
  let amountText = $state(start.amount);
  let date = $state.raw(start.date);
  let note = $state(start.note);

  /// Accepte « 12,50 », « 12.50 » ou « 1 234,5 ».
  const parsedAmount = $derived.by(() => {
    const cents = parseAmount(amountText);
    return cents !== null && cents > 0 ? cents : null;
  });

  /// Comptes sélectionnables, plus ceux déjà utilisés par le virement édité (archivés ou Izly).
  const availableAccounts = $derived.by((): Account[] => {
    const list = [...store.selectableAccounts];
    for (const id of legs ? [resolvedAccountID(legs.out), resolvedAccountID(legs.in)] : []) {
      if (!list.some(a => a.id === id)) list.push(store.account(id));
    }
    return list.filter(a => a.id !== lockedToID);
  });

  const canSave = $derived(parsedAmount !== null && fromID !== "" && toID !== "" && fromID !== toID);

  /// Solde d'un compte sans l'effet du virement édité.
  function baseBalance(id: string): number {
    let value = balance(store, store.account(id));
    if (legs) {
      if (resolvedAccountID(legs.out) === id) value += legs.out.amountCents;
      if (resolvedAccountID(legs.in) === id) value -= legs.in.amountCents;
    }
    return value;
  }

  const warnings = $derived.by((): string[] => {
    if (parsedAmount === null || !canSave) return [];
    const result: string[] = [];
    const from = store.account(fromID);
    const to = store.account(toID);
    const after = baseBalance(fromID) - parsedAmount;
    if (after < 0) result.push(`Le solde de « ${from.name} » passera à ${euros(after)}.`);
    const ceiling = accountKinds[to.kind].ceilingCents;
    if (ceiling !== null) {
      const total = baseBalance(toID) + parsedAmount;
      if (total > ceiling) result.push(`« ${to.name} » dépassera son plafond de ${euros(ceiling)} (${euros(total)}).`);
    }
    return result;
  });

  const title = $derived(lockedToID ? "Recharger" : isNew ? "Nouveau virement" : "Modifier le virement");

  function save() {
    if (parsedAmount === null || !canSave) return;
    if (transferID) updateTransfer(store, transferID, fromID, toID, parsedAmount, date, note);
    else createTransfer(store, fromID, toID, parsedAmount, date, note);
    onclose();
  }

  async function remove() {
    if (!transferID) return;
    const ok = await confirmDialog("Les deux opérations liées seront supprimées.", {
      title: "Supprimer ce virement ?", okLabel: "Supprimer le virement" });
    if (!ok) return;
    deleteTransfer(store, transferID);
    onclose();
  }

  function swap() { [fromID, toID] = [toID, fromID]; }
</script>

{#snippet picker(heading: string, selected: string, excluded: string, choose: (id: string) => void)}
  <Card>
    <div class="col">
      <span class="caption">{heading}</span>
      <div class="accounts">
        {#each availableAccounts as account (account.id)}
          <button type="button" class="account" class:selected={selected === account.id} disabled={account.id === excluded}
                  onclick={() => choose(account.id)}>
            <AccountBadge {account} size={32} />
            <span class="names">
              <span class="truncate">{account.name}</span>
              <span class="caption nums truncate">{euros(balance(store, account))}</span>
            </span>
          </button>
        {/each}
      </div>
    </div>
  </Card>
{/snippet}

<Sheet {title} {onclose} width={480}>
  <AmountField bind:value={amountText} onenter={save} />

  {#if lockedToID}
    <div class="shortcuts">
      {#each [10, 20, 50] as value (value)}
        <button type="button" class="btn" onclick={() => (amountText = String(value))}>{value} €</button>
      {/each}
    </div>
    {@render picker("Depuis", fromID, toID, (id) => (fromID = id))}
  {:else}
    {@render picker("De", fromID, toID, (id) => (fromID = id))}
    <button type="button" class="swap" title="Inverser les comptes" aria-label="Inverser les comptes" onclick={swap}>
      <Icon name="arrow.up.arrow.down" size={16} />
    </button>
    {@render picker("Vers", toID, fromID, (id) => (toID = id))}
  {/if}

  {#each warnings as warning (warning)}
    <div class="warning-line caption warning"><Icon name="exclamationmark.triangle.fill" size={13} /><span>{warning}</span></div>
  {/each}

  <Card><DateField value={date} onchange={(d) => (date = d)} /></Card>

  <Card>
    <textarea class="bare" rows="1" placeholder="Virement" aria-label="Note" bind:value={note}></textarea>
  </Card>

  {#if !isNew}
    <button type="button" class="delete" onclick={remove}>Supprimer le virement</button>
  {/if}

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .shortcuts { display: flex; justify-content: center; gap: var(--spacing); }
  .accounts { display: flex; gap: var(--spacing); overflow-x: auto; padding: 2px; }
  .account {
    display: inline-flex; align-items: center; gap: var(--spacing); flex-shrink: 0; max-width: 240px; text-align: left;
    padding: var(--spacing); border-radius: var(--radius-small); background: var(--surface-secondary);
    border: 1.5px solid transparent; color: var(--text-primary);
  }
  .account.selected { background: color-mix(in srgb, var(--accent) 15%, transparent); border-color: var(--accent); }
  .account:disabled { opacity: 0.4; }
  .names { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .names .caption { color: var(--text-secondary); }
  .swap {
    align-self: center; width: 36px; height: 36px; border-radius: 50%; border: none; flex-shrink: 0;
    display: inline-flex; align-items: center; justify-content: center;
    background: var(--accent); color: var(--on-accent);
  }
  .warning-line { display: flex; align-items: flex-start; gap: 6px; }
  .bare {
    width: 100%; border: none; outline: none; background: transparent; padding: 0; resize: vertical;
    color: var(--text-primary); font-size: var(--body);
  }
  .bare::placeholder { color: var(--text-tertiary); }
  .delete { align-self: center; border: none; background: transparent; color: var(--warning); padding: 6px; }
</style>
