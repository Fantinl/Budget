<script lang="ts">
  // Étape « Ton compte par défaut » (accountStep d'OnboardingView.swift) : compte principal, autres comptes, Izly.
  import { store } from "../../lib/app.svelte";
  import { type AccountFamily, MAIN_ACCOUNT_ID, accountKinds, families, hasMarketValue, kindsInFamily } from "../../lib/model";
  import { euros } from "../../lib/format";
  import { accountUsageCount, banks, hidesBank, selectableKinds } from "../../lib/logic/accounts";
  import { type AccountDraft, parsedBalanceCents, refreshName, trimmedBank } from "../accounts/accountDraft";
  import { requestAccountDeletion } from "../accounts/accountDeletion";
  import { categoryColor } from "../../lib/theme.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import AccountBadge from "../../ui/AccountBadge.svelte";
  import Chip from "./Chip.svelte";
  import NumberField from "./NumberField.svelte";
  import StepHeader from "./StepHeader.svelte";
  import IzlyCard from "./IzlyCard.svelte";
  import AccountEditor from "../accounts/AccountEditor.svelte";
  import { commonBanks } from "./items";

  let { draft, isStudent, showIzly, izlyOn = $bindable(true), izlyBalance = $bindable("") }: {
    draft: AccountDraft; isStudent: boolean; showIzly: boolean; izlyOn?: boolean; izlyBalance?: string;
  } = $props();

  let adding = $state(false);

  const familyShort: Record<AccountFamily, string> = { current: "Courant", savings: "Épargne", investment: "Investissement", other: "Autre" };
  const kind = $derived(draft.account.kind);
  const family = $derived(accountKinds[kind].family);
  const mainHasTransactions = $derived(accountUsageCount(store, store.account(MAIN_ACCOUNT_ID)) > 0);
  const otherAccounts = $derived(store.accounts.filter(a => a.id !== MAIN_ACCOUNT_ID && !a.isArchived));
  const balance = $derived(parsedBalanceCents(draft));
  const name = $derived(draft.account.name.trim());
  const subtitle = $derived([trimmedBank(draft) === "" || hidesBank(kind) ? null : trimmedBank(draft), accountKinds[kind].label].filter(Boolean).join(" · "));
  const balanceTitle = $derived(mainHasTransactions ? "Solde initial" : hasMarketValue(kind) ? "Versements initiaux" : "Solde actuel");

  const bankSuggestions = $derived.by(() => {
    const typed = trimmedBank(draft).toLowerCase();
    const known = banks(store);
    const extra = commonBanks.filter(n => !known.some(k => k.toLowerCase() === n.toLowerCase()));
    return [...known, ...extra].filter(b => typed === "" || (b.toLowerCase().includes(typed) && b.toLowerCase() !== typed));
  });

  function setKind(k: typeof kind) { draft.account.kind = k; refreshName(draft); }
  function setBank(text: string) { draft.bankText = text; refreshName(draft); }
  function pickFamily(f: AccountFamily) {
    if (family === f) return;
    const first = kindsInFamily(f)[0];
    if (first) setKind(first);
  }

  function subtitleOf(a: (typeof otherAccounts)[number]) {
    return [a.bank && !hidesBank(a.kind) ? a.bank : null, accountKinds[a.kind].label].filter(Boolean).join(" · ");
  }
</script>

<div class="col" style:gap="var(--padding)">
  <StepHeader title="Ton compte par défaut" subtitle="Le compte utilisé par défaut pour tes opérations." />

  <div class="preview" style:--c={categoryColor(draft.account.colorIndex)}>
    <AccountBadge account={draft.account} size={52} />
    <div class="texts">
      <span class="title truncate" class:tertiary={name === ""}>{name === "" ? "Nom du compte" : name}</span>
      <span class="caption truncate">{subtitle}</span>
    </div>
    <span class="spacer"></span>
    {#if balance !== null}<span class="amount">{euros(balance)}</span>{/if}
  </div>

  <Card>
    <span class="caption">Type de compte</span>
    <div class="chips">
      {#each families as f (f)}
        <Chip title={familyShort[f]} icon={accountKinds[kindsInFamily(f)[0]].icon} selected={family === f} onclick={() => pickFamily(f)} />
      {/each}
    </div>
    <hr class="separator" />
    <div class="chips">
      {#each selectableKinds(family, false, kind) as option (option)}
        <Chip title={accountKinds[option].label} icon={accountKinds[option].icon} selected={kind === option} onclick={() => setKind(option)} />
      {/each}
    </div>
  </Card>

  {#if !hidesBank(kind)}
    <Card>
      <span class="caption">Banque</span>
      <input class="plain" placeholder="Facultatif" aria-label="Banque" value={draft.bankText} oninput={(e) => setBank(e.currentTarget.value)} />
      {#if bankSuggestions.length > 0}
        <div class="chips">{#each bankSuggestions as bank (bank)}<Chip title={bank} onclick={() => setBank(bank)} />{/each}</div>
      {/if}
    </Card>
  {/if}

  <Card>
    <span class="caption">Nom</span>
    <input class="plain" placeholder="Nom du compte" aria-label="Nom" bind:value={draft.account.name} oninput={() => (draft.nameIsAuto = false)} />
  </Card>

  <Card>
    <div class="row">
      <span>{balanceTitle}</span>
      <span class="spacer"></span>
      <NumberField title={balanceTitle} bind:value={draft.balanceText} unit="€" width={110} />
    </div>
    <span class="caption">
      {mainHasTransactions
        ? "Ce compte contient déjà des opérations : son solde = solde initial + revenus − dépenses. Peut être négatif."
        : "Le montant actuellement sur le compte. Les opérations que tu saisiras ensuite s’y ajouteront. Peut être négatif."}
    </span>
  </Card>

  <div class="col">
    <span class="title">Autres comptes</span>
    <span class="caption">Livret A, épargne, espèces… Facultatif, tu pourras en ajouter plus tard.</span>
    <Card>
      {#each otherAccounts as account (account.id)}
        <div class="row">
          <AccountBadge {account} size={34} />
          <div class="texts">
            <span class="truncate">{account.name}</span>
            <span class="caption truncate">{subtitleOf(account)}</span>
          </div>
          <span class="spacer"></span>
          <span class="amount secondary">{euros(account.initialBalanceCents)}</span>
          <button type="button" class="remove" title="Retirer ce compte" aria-label="Retirer ce compte" onclick={() => requestAccountDeletion(store, account)}>
            <Icon name="minus.circle.fill" size={18} color="var(--negative)" />
          </button>
        </div>
        <hr class="separator" />
      {/each}
      <button type="button" class="add" onclick={() => (adding = true)}>
        <Icon name="plus.circle.fill" size={18} color="var(--accent)" /> <span>Ajouter un autre compte</span>
      </button>
    </Card>
  </div>

  {#if isStudent && showIzly}
    <IzlyCard bind:isOn={izlyOn} bind:balanceText={izlyBalance} />
  {/if}
</div>

{#if adding}<AccountEditor account={null} onclose={() => (adding = false)} />{/if}

<style>
  .preview {
    display: flex; align-items: center; gap: var(--padding); padding: var(--padding); border-radius: var(--radius);
    background: color-mix(in srgb, var(--c) calc(var(--badge-opacity) * 100%), transparent); border: 1.5px solid var(--c);
  }
  .texts { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .chips { display: flex; flex-wrap: wrap; gap: var(--spacing); }
  .plain { border: none; outline: none; background: transparent; color: var(--text-primary); padding: 2px 0; width: 100%; }
  .remove { border: none; background: transparent; padding: 0; display: inline-flex; }
  .add { border: none; background: transparent; padding: 0; color: var(--accent); display: flex; align-items: center; gap: 8px; text-align: left; }
</style>
