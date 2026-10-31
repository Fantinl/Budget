<script lang="ts">
  // Feuille de création / modification d'un compte (AccountEditorSheet de AccountEditor.swift).
  import { store } from "../../lib/app.svelte";
  import { fromInputDate, toInputDate } from "../../lib/dates";
  import { type Account, type AccountFamily, type AccountKind, accountKinds, families, hasMarketValue, kindsInFamily, MAIN_ACCOUNT_ID } from "../../lib/model";
  import { banks, hidesBank, selectableKinds, upsertAccount } from "../../lib/logic/accounts";
  import { hasRegulatedRate, regulatedRate } from "../../lib/logic/rates";
  import { prefs } from "../../lib/prefs.svelte";
  import { categoryColor } from "../../lib/theme.svelte";
  import AccountBadge from "../../ui/AccountBadge.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import Sheet from "../../ui/Sheet.svelte";
  import { requestAccountDeletion } from "./accountDeletion";
  import {
    autoRateActive, draftFrom, newDraft, refreshName, showsRate, trimmedBank, validated, type AccountDraft,
  } from "./accountDraft";

  /// `account` = compte à modifier, null = nouveau compte.
  let { account: source, onclose }: { account: Account | null; onclose: () => void } = $props();

  const commonBanks = [
    "BNP Paribas", "Société Générale", "Crédit Agricole", "Crédit Mutuel", "LCL", "La Banque Postale",
    "Caisse d’Épargne", "Banque Populaire", "Boursorama", "Fortuneo", "Hello bank!", "Revolut", "N26", "Trade Republic",
  ];
  const familyShort: Record<AccountFamily, string> = { current: "Courant", savings: "Épargne", investment: "Investissement", other: "Autre" };
  const dateFormat = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "long", year: "numeric" });
  const ceilingFormat = new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
  const rateFormat = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 });

  // svelte-ignore state_referenced_locally
  let draft = $state<AccountDraft>(source ? draftFrom(source) : newDraft(store.accounts.length));

  const kind = $derived(draft.account.kind);
  const isMain = $derived(draft.account.id === MAIN_ACCOUNT_ID);
  const canSave = $derived(validated(draft) !== null);
  const today = toInputDate(new Date());

  const name = $derived(draft.account.name.trim());
  const subtitle = $derived([trimmedBank(draft).length === 0 || hidesBank(kind) ? null : trimmedBank(draft), accountKinds[kind].label]
    .filter(Boolean).join(" · "));
  const color = $derived(categoryColor(draft.account.colorIndex));

  const suggestions = $derived.by(() => {
    const typed = trimmedBank(draft).toLowerCase();
    const known = banks(store);
    const extra = commonBanks.filter(b => !known.some(k => k.toLowerCase() === b.toLowerCase()));
    return [...known, ...extra].filter(b => typed.length === 0 || (b.toLowerCase().includes(typed) && b.toLowerCase() !== typed));
  });

  function setKind(newKind: AccountKind) {
    draft.account.kind = newKind;
    refreshName(draft);
  }

  function chooseFamily(family: AccountFamily) {
    const first = kindsInFamily(family)[0];
    if (accountKinds[kind].family === family || !first) return;
    setKind(first);
  }

  const autoRateText = $derived.by(() => {
    const probe = { ...draft.account };
    if (kind === "pel" && !probe.openingDate) probe.openingDate = new Date();
    const regulated = regulatedRate(store, probe);
    if (!regulated) return "Taux non disponible pour cette date d’ouverture.";
    const since = regulated.since ? ` depuis le ${dateFormat.format(regulated.since)}` : "";
    const prefix = regulated.isMinimum ? "Minimum " : "";
    const suffix = kind === "pel" ? " (fixé à l’ouverture)" : regulated.isMinimum ? " : ta banque peut proposer plus" : "";
    return `${prefix}${rateFormat.format(regulated.rate)} %${since}${suffix}`;
  });

  function save() {
    const account = validated(draft);
    if (!account) return;
    upsertAccount(store, $state.snapshot(account) as Account);
    onclose();
  }

  async function remove() {
    if (await requestAccountDeletion(store, $state.snapshot(draft.account) as Account)) onclose();
  }
</script>

<Sheet title={draft.isNew ? "Nouveau compte" : "Modifier le compte"} {onclose} width={500}>
  <div class="preview" style:--c={color}>
    <AccountBadge account={draft.account} size={52} />
    <div class="col tight names">
      <span class="title truncate" class:tertiary={name.length === 0}>{name.length === 0 ? "Nom du compte" : name}</span>
      <span class="caption truncate">{subtitle}</span>
    </div>
  </div>

  <Card>
    <span class="caption">Type de compte</span>
    <div class="chips">
      {#each families as family (family)}
        {@const selected = accountKinds[kind].family === family}
        <button type="button" class="chip" class:selected onclick={() => chooseFamily(family)}>
          <Icon name={accountKinds[kindsInFamily(family)[0]].icon} size={13} /> <span>{familyShort[family]}</span>
        </button>
      {/each}
    </div>
    <hr class="separator" />
    <div class="chips">
      {#each selectableKinds(accountKinds[kind].family, prefs.studentProfile.value, kind) as option (option)}
        <button type="button" class="chip" class:selected={kind === option} onclick={() => setKind(option)}>
          <Icon name={accountKinds[option].icon} size={13} /> <span>{accountKinds[option].label}</span>
        </button>
      {/each}
    </div>
    {#if accountKinds[kind].ceilingCents !== null}
      <span class="caption">Plafond : {ceilingFormat.format(accountKinds[kind].ceilingCents / 100)}</span>
    {/if}
  </Card>

  {#if !hidesBank(kind)}
    <Card>
      <span class="caption">Banque</span>
      <input class="plain-input" type="text" placeholder="Facultatif" aria-label="Banque" value={draft.bankText}
             oninput={(e) => { draft.bankText = e.currentTarget.value; refreshName(draft); }} />
      {#if suggestions.length > 0}
        <div class="chips">
          {#each suggestions as bank (bank)}
            <button type="button" class="chip" onclick={() => { draft.bankText = bank; refreshName(draft); }}><span>{bank}</span></button>
          {/each}
        </div>
      {/if}
    </Card>
  {/if}

  <Card>
    <span class="caption">Nom</span>
    <input class="plain-input" type="text" placeholder="Nom du compte" aria-label="Nom" value={draft.account.name}
           oninput={(e) => { draft.account.name = e.currentTarget.value; draft.nameIsAuto = false; }} />
  </Card>

  <Card>
    <label class="line amount-row">
      <span>{hasMarketValue(kind) ? "Versements initiaux" : "Solde initial"}</span>
      <span class="row tight"><input class="plain-input right" type="text" inputmode="decimal" placeholder="0,00" bind:value={draft.balanceText} /><span class="secondary">€</span></span>
    </label>
    <span class="caption">
      {hasMarketValue(kind) ? "Total déjà versé avant les opérations saisies ici."
        : "Le solde actuel = solde initial + revenus − dépenses du compte. Peut être négatif."}
    </span>

    {#if showsRate(draft)}
      <hr class="separator" />
      {#if hasRegulatedRate(kind)}
        <label class="line amount-row">
          <span>Taux automatique (réglementé)</span>
          <input type="checkbox" class="switch" checked={draft.account.autoRate !== false}
                 onchange={(e) => (draft.account.autoRate = e.currentTarget.checked ? null : false)} />
        </label>
        {#if kind === "pel"}
          <label class="line amount-row">
            <span>Date d’ouverture</span>
            <input class="field" type="date" max={today} value={toInputDate(draft.account.openingDate ?? new Date())}
                   onchange={(e) => { const d = fromInputDate(e.currentTarget.value); if (d) draft.account.openingDate = d; }} />
          </label>
        {/if}
        {#if autoRateActive(draft)}
          <span class="caption">{autoRateText}</span>
        {:else}
          <label class="line amount-row">
            <span>Taux annuel</span>
            <span class="row tight"><input class="plain-input right" type="text" inputmode="decimal" placeholder="Facultatif" bind:value={draft.rateText} /><span class="secondary">%</span></span>
          </label>
        {/if}
      {:else}
        <label class="line amount-row">
          <span>Taux annuel</span>
          <span class="row tight"><input class="plain-input right" type="text" inputmode="decimal" placeholder="Facultatif" bind:value={draft.rateText} /><span class="secondary">%</span></span>
        </label>
        <span class="caption">Taux propre à ta banque : à saisir.</span>
      {/if}
    {/if}

    {#if hasMarketValue(kind)}
      <hr class="separator" />
      <label class="line amount-row">
        <span>Valorisation actuelle</span>
        <span class="row tight"><input class="plain-input right" type="text" inputmode="decimal" placeholder="Facultatif" bind:value={draft.marketValueText} /><span class="secondary">€</span></span>
      </label>
      <label class="line amount-row">
        <span>Date de valorisation</span>
        <input class="field" type="date" max={today} value={toInputDate(draft.marketValueDate)}
               onchange={(e) => { const d = fromInputDate(e.currentTarget.value); if (d) draft.marketValueDate = d; }} />
      </label>
      <span class="caption">À mettre à jour de temps en temps depuis ton appli de banque.</span>
    {/if}
  </Card>

  <Card>
    <span class="caption">Couleur</span>
    <div class="palette">
      {#each Array.from({ length: 12 }, (_, i) => i) as index (index)}
        <button type="button" class="swatch" style:background={categoryColor(index)} aria-label="Couleur {index + 1}"
                onclick={() => (draft.account.colorIndex = index)}>
          {#if draft.account.colorIndex === index}<Icon name="checkmark" size={14} color="var(--on-accent)" strokeWidth={3} />{/if}
        </button>
      {/each}
    </div>
  </Card>

  {#if !draft.isNew && !isMain}
    <div class="danger col">
      <button type="button" class="link accent" onclick={() => (draft.account.isArchived = !draft.account.isArchived)}>
        {draft.account.isArchived ? "Désarchiver le compte" : "Archiver le compte"}
      </button>
      <button type="button" class="link negative" onclick={remove}>Supprimer le compte</button>
    </div>
  {/if}

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .preview {
    display: flex; align-items: center; gap: var(--padding); padding: var(--padding); border-radius: var(--radius);
    background: color-mix(in srgb, var(--c) calc(var(--badge-opacity) * 100%), transparent); border: 1.5px solid var(--c);
  }
  .names { min-width: 0; flex: 1; }
  .chips { display: flex; flex-wrap: wrap; gap: var(--spacing); }
  .chip {
    display: inline-flex; align-items: center; gap: 6px; padding: 7px var(--spacing); border-radius: 999px; max-width: 100%;
    border: 1.5px solid transparent; background: var(--surface-secondary); color: var(--text-secondary); font-size: var(--caption);
  }
  .chip.selected { background: color-mix(in srgb, var(--accent) 15%, transparent); border-color: var(--accent); color: var(--text-primary); }
  .chip span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .plain-input { border: none; outline: none; background: transparent; color: var(--text-primary); min-width: 0; width: 100%; }
  .plain-input.right { text-align: right; width: 120px; }
  .amount-row { align-items: center; }
  .palette { display: grid; grid-template-columns: repeat(auto-fill, minmax(36px, 1fr)); gap: 8px; }
  .swatch { width: 28px; height: 28px; border-radius: 50%; border: none; display: inline-flex; align-items: center; justify-content: center; }
  .danger { align-items: center; padding-top: calc(var(--spacing) / 2); gap: var(--spacing); }
  .link { border: none; background: none; padding: 0; }
  .link.accent { color: var(--accent); }
  .link.negative { color: var(--negative); }
</style>
