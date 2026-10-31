<script lang="ts">
  // Feuille « Modifier ensemble » : les champs identiques dans toute la sélection sont pré-remplis, les autres
  // affichent « Plusieurs valeurs » et ne sont modifiés que si l'utilisateur les change. Port de BulkEditSheet.swift.
  import { untrack } from "svelte";
  import { type Category, type Kind, type Tag, type Transaction, isTransfer, kindLabel } from "../../lib/model";
  import { store } from "../../lib/app.svelte";
  import { amountInput } from "../../lib/format";
  import { positiveAmount } from "../../lib/logic/amountExpression";
  import { type BulkEdit, type BulkTagState, applyBulkEdit, bulkSummary, emptyBulkEdit, isBulkEditEmpty, isUniform, tagState } from "../../lib/logic/bulk";
  import { addTag } from "../../lib/logic/tags";
  import Sheet from "../../ui/Sheet.svelte";
  import Card from "../../ui/Card.svelte";
  import TagChip from "../../ui/TagChip.svelte";
  import Icon from "../../ui/Icon.svelte";
  import AmountHint from "./AmountHint.svelte";

  let { transactions, onclose }: { transactions: Transaction[]; onclose: () => void } = $props();

  const all = untrack(() => transactions);
  const editable = all.filter(t => !isTransfer(t));
  const summary = bulkSummary(editable);
  const ids = new Set(editable.map(t => t.id));
  const skippedTransfers = all.length - editable.length;
  const initialAmountText = summary.amountCents === null ? null : amountInput(summary.amountCents);
  const kinds: Kind[] = ["expense", "income"];

  let amountText = $state(initialAmountText ?? "");
  let kind = $state<Kind | null>(summary.kind);
  let categoryID = $state<string | null>(summary.categoryID);
  let accountID = $state<string | null>(summary.accountID);
  let noteText = $state(summary.note ?? "");
  /// true = ajouter, false = retirer
  let tagOps = $state<Record<string, boolean>>({});
  let newTagName = $state("");

  // MARK: Valeurs à enregistrer

  const amountChanged = $derived(amountText !== (initialAmountText ?? ""));
  const parsedAmount = $derived(positiveAmount(amountText));
  const amountInvalid = $derived(amountChanged && parsedAmount === null);

  const edit = $derived.by((): BulkEdit => {
    const e = emptyBulkEdit();
    if (amountChanged && parsedAmount !== null) e.amountCents = parsedAmount;
    if (kind !== summary.kind && kind !== null) e.kind = kind;
    if (categoryID !== summary.categoryID && categoryID !== null) e.categoryID = categoryID;
    if (accountID !== summary.accountID && accountID !== null) e.accountID = accountID;
    if (noteText !== (summary.note ?? "")) e.note = noteText;
    e.addTagIDs = Object.entries(tagOps).filter(([, add]) => add).map(([id]) => id);
    e.removeTagIDs = Object.entries(tagOps).filter(([, add]) => !add).map(([id]) => id);
    return e;
  });

  const hasNewTag = $derived(newTagName.trim().length > 0);
  const canSave = $derived(!amountInvalid && (!isBulkEditEmpty(edit) || hasNewTag));

  const plural = (n: number) => (n > 1 ? "s" : "");

  // MARK: Type et catégorie

  function setKind(value: string) {
    kind = value === "" ? null : (value as Kind);
    // Changement de type : la catégorie doit suivre.
    if (kind && categoryID && store.category(categoryID).kind !== kind) categoryID = store.categoriesFor(kind)[0]?.id ?? null;
  }

  /// Types de catégories proposés : le type choisi, sinon ceux de la sélection.
  const categoryKinds = $derived<Kind[]>(kind ? [kind] : kinds);

  function categoryOptions(forKind: Kind): Category[] {
    const options = store.categoriesFor(forKind);
    const id = categoryID ?? summary.categoryID;
    if (id && !options.some(c => c.id === id) && store.category(id).kind === forKind) options.push(store.category(id));
    return options;
  }

  /// Comptes sélectionnables, plus le compte commun actuel s'il n'en fait pas partie (Izly).
  const accountOptions = $derived.by(() => {
    const options = [...store.selectableAccounts];
    if (summary.accountID && !options.some(a => a.id === summary.accountID)) options.push(store.account(summary.accountID));
    return options;
  });

  // MARK: Dates

  const dayMonth = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short" });
  const dayOnly = new Intl.DateTimeFormat("fr-FR", { day: "numeric" });
  const dateRange = $derived.by(() => {
    const { firstDate: first, lastDate: last } = summary;
    if (!first || !last) return "";
    if (first.toDateString() === last.toDateString()) return dayMonth.format(first);
    return `du ${dayOnly.format(first)} au ${dayMonth.format(last)}`;
  });

  // MARK: Tags

  function displayedState(tag: Tag): BulkTagState {
    const op = tagOps[tag.id];
    if (op === true) return "all";
    if (op === false) return "none";
    return tagState(store, tag.id, ids);
  }

  function toggle(tag: Tag, state: BulkTagState) {
    const original = tagState(store, tag.id, ids);
    const target = state !== "all"; // tout ajouter sauf si déjà partout
    const next = { ...tagOps };
    // Revenir à l'état d'origine annule l'opération en attente.
    if ((target && original === "all") || (!target && original === "none")) delete next[tag.id];
    else next[tag.id] = target;
    tagOps = next;
  }

  // MARK: Enregistrement

  function save() {
    const e = { ...edit, addTagIDs: [...edit.addTagIDs] };
    if (hasNewTag) e.addTagIDs.push(addTag(store, newTagName).id);
    applyBulkEdit(store, ids, e);
    onclose();
  }
</script>

<Sheet title={`Modifier ${summary.count} opération${plural(summary.count)}`} {onclose} width={440}>
  {#if isUniform(summary)}
    <span class="caption note">{summary.count} opérations identiques : les modifications s’appliqueront à toutes</span>
  {/if}
  {#if skippedTransfers > 0}
    <span class="caption note">{skippedTransfers} virement{plural(skippedTransfers)} ignoré{plural(skippedTransfers)}</span>
  {/if}

  <Card>
    <div class="col tight">
      <span class="caption">Montant</span>
      <div class="row tight">
        <input class="bare" type="text" aria-label="Montant" bind:value={amountText}
               placeholder={summary.amountCents === null ? "Plusieurs valeurs" : "0,00"} />
        <span class="secondary">€</span>
      </div>
      <AmountHint text={amountText} />
    </div>
  </Card>

  <Card>
    <div class="col tight">
      <span class="caption">Type</span>
      <select class="field" aria-label="Type" value={kind ?? ""} onchange={(e) => setKind(e.currentTarget.value)}>
        {#if summary.kind === null}<option value="">Plusieurs valeurs</option>{/if}
        {#each kinds as k (k)}<option value={k}>{kindLabel[k]}</option>{/each}
      </select>
      <span class="caption">Catégorie</span>
      <select class="field" aria-label="Catégorie" value={categoryID ?? ""}
              onchange={(e) => (categoryID = e.currentTarget.value === "" ? null : e.currentTarget.value)}>
        {#if summary.categoryID === null}<option value="">Plusieurs valeurs</option>{/if}
        {#each categoryKinds as k (k)}
          <optgroup label={kindLabel[k]}>
            {#each categoryOptions(k) as c (c.id)}<option value={c.id}>{c.label}</option>{/each}
          </optgroup>
        {/each}
      </select>
    </div>
  </Card>

  <Card>
    <div class="col tight">
      <span class="caption">Compte</span>
      <select class="field" aria-label="Compte" value={accountID ?? ""}
              onchange={(e) => (accountID = e.currentTarget.value === "" ? null : e.currentTarget.value)}>
        {#if summary.accountID === null}<option value="">Plusieurs valeurs</option>{/if}
        {#each accountOptions as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
      </select>
    </div>
  </Card>

  <Card>
    <div class="col tight">
      <span class="caption">Description</span>
      <textarea class="bare" rows="2" aria-label="Description" bind:value={noteText}
                placeholder={summary.note === null ? "Plusieurs valeurs" : "Facultatif"}></textarea>
    </div>
  </Card>

  <Card>
    <div class="col tight">
      {#if store.tags.length > 0}
        <span class="caption">Tags</span>
        <div class="tags">
          {#each store.tags as tag (tag.id)}
            {@const state = displayedState(tag)}
            <button type="button" class="tag" onclick={() => toggle(tag, state)}>
              {#if state !== "none"}<Icon name={state === "all" ? "checkmark" : "minus"} size={12} />{/if}
              <TagChip text={tag.name} colorIndex={tag.colorIndex} selected={state !== "none"} />
            </button>
          {/each}
        </div>
      {/if}
      <input class="bare" type="text" placeholder="Nouveau tag" aria-label="Nouveau tag" bind:value={newTagName} />
    </div>
  </Card>

  <Card>
    <div class="line">
      <span class="caption">Dates</span>
      <span class="secondary">{dateRange}</span>
    </div>
  </Card>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .note { text-align: left; }
  select.field { width: 100%; }
  .bare {
    width: 100%; border: none; outline: none; background: transparent; padding: 0; resize: vertical;
    color: var(--text-primary); font-size: var(--body);
  }
  .bare::placeholder { color: var(--text-tertiary); }
  .tags { display: grid; grid-template-columns: repeat(auto-fill, minmax(80px, max-content)); gap: var(--spacing); }
  .tag { display: inline-flex; align-items: center; gap: 4px; border: none; background: transparent; padding: 0; justify-self: start; color: var(--text-secondary); }
</style>
