<script lang="ts">
  // Création / modification d'un modèle de dépense rapide (SettingsQuickSheet).
  import { store } from "../../lib/app.svelte";
  import { type Kind, type QuickExpense, kindLabel } from "../../lib/model";
  import { amountInput, euros } from "../../lib/format";
  import { containsOperator, evaluate, positiveAmount } from "../../lib/logic/amountExpression";
  import Sheet from "../../ui/Sheet.svelte";

  let { quick, isNew, onclose }: { quick: QuickExpense; isNew: boolean; onclose: () => void } = $props();

  const kinds: Kind[] = ["expense", "income"];
  // svelte-ignore state_referenced_locally
  let draft = $state<QuickExpense>({ ...quick });
  // svelte-ignore state_referenced_locally
  let amountText = $state(isNew ? "" : amountInput(quick.amountCents));

  const amount = $derived(positiveAmount(amountText));
  const categories = $derived(store.categoriesFor(draft.kind));
  const canSave = $derived(draft.name.trim() !== "" && amount !== null && categories.some(c => c.id === draft.categoryID));

  /// Comptes proposés : les sélectionnables, plus le compte déjà choisi s'il n'en fait pas partie (ex. Izly).
  const accountChoices = $derived.by(() => {
    const choices = store.selectableAccounts;
    const current = draft.accountID ? store.accounts.find(a => a.id === draft.accountID) : undefined;
    return current && !choices.some(a => a.id === current.id) ? [...choices, current] : choices;
  });

  /// Sélectionne une catégorie valide pour le type courant.
  $effect.pre(() => {
    if (!categories.some(c => c.id === draft.categoryID)) draft.categoryID = categories[0]?.id ?? "";
  });

  function save() {
    if (!canSave || amount === null) return;
    store.upsertQuickExpense({ ...draft, name: draft.name.trim(), amountCents: amount });
    onclose();
  }
</script>

<Sheet title={isNew ? "Nouveau modèle" : "Modifier le modèle"} {onclose} width={440}>
  <label class="form-row"><span>Nom</span>
    <!-- svelte-ignore a11y_autofocus -->
    <input class="field" bind:value={draft.name} autofocus /></label>
  <label class="form-row"><span>Montant</span>
    <input class="field" inputmode="decimal" bind:value={amountText} onkeydown={(e) => { if (e.key === "Enter") save(); }} /></label>
  {#if containsOperator(amountText)}
    {@const value = evaluate(amountText)}
    {#if value !== null}<span class="caption nums hint">= {euros(value)}</span>
    {:else}<span class="caption negative hint">Calcul invalide</span>{/if}
  {/if}
  <div class="form-row"><span>Type</span>
    <span class="segmented" role="group" aria-label="Type">
      {#each kinds as k (k)}
        <button type="button" class:selected={draft.kind === k} onclick={() => (draft.kind = k)}>{kindLabel[k]}</button>
      {/each}
    </span></div>
  <label class="form-row"><span>Catégorie</span>
    <select class="field" bind:value={draft.categoryID}>
      {#each categories as c (c.id)}<option value={c.id}>{c.label}</option>{/each}
    </select></label>
  <label class="form-row"><span>Note</span>
    <input class="field" placeholder="Note (facultative)" bind:value={draft.note} /></label>
  <!-- Choix du compte seulement s'il y en a plusieurs (null = compte par défaut). -->
  {#if accountChoices.length > 1}
    <label class="form-row"><span>Compte</span>
      <select class="field" value={draft.accountID ?? ""} onchange={(e) => (draft.accountID = e.currentTarget.value || null)}>
        <option value="">Compte par défaut</option>
        {#each accountChoices as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
      </select></label>
  {/if}
  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .hint { margin-left: 152px; }
  .segmented { justify-self: start; }
  .form-row { display: grid; grid-template-columns: 140px 1fr; align-items: center; gap: var(--spacing); }
  .form-row > span:first-child { color: var(--text-secondary); }
</style>
