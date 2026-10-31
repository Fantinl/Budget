<script lang="ts">
  // Création / modification d'une catégorie (SettingsCategorySheet).
  import { store } from "../../lib/app.svelte";
  import { type Category, type Kind, kindLabel } from "../../lib/model";
  import { parseAmount } from "../../lib/format";
  import { categorySymbols } from "../../ui/icons";
  import Sheet from "../../ui/Sheet.svelte";
  import Icon from "../../ui/Icon.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Swatches from "./Swatches.svelte";
  import { confirmDeleteCategory } from "./CategoryDeletion";

  let { category, isNew, onclose }: { category: Category; isNew: boolean; onclose: () => void } = $props();

  const kinds: Kind[] = ["expense", "income"];
  // Copie de travail : le brouillon vit le temps de la feuille.
  // svelte-ignore state_referenced_locally
  let draft = $state<Category>({ ...category });
  // svelte-ignore state_referenced_locally
  let budgetText = $state(category.monthlyBudgetCents ? budgetToText(category.monthlyBudgetCents) : "");

  function budgetToText(cents: number): string {
    return (cents % 100 === 0 ? String(cents / 100) : (cents / 100).toString()).replace(".", ",");
  }

  /// Budget saisi : null si vide ou invalide (virgule acceptée), doit être > 0.
  const parsedBudget = $derived.by(() => {
    const cents = parseAmount(budgetText.trim());
    return cents !== null && cents > 0 ? cents : null;
  });
  const budgetIsValid = $derived(budgetText.trim() === "" || parsedBudget !== null);
  const canSave = $derived(draft.label.trim() !== "" && budgetIsValid);

  function save() {
    if (!canSave) return;
    store.upsertCategory({ ...draft, label: draft.label.trim(), monthlyBudgetCents: draft.kind === "expense" ? parsedBudget : null });
    onclose();
  }

  async function remove() {
    if (await confirmDeleteCategory(store, draft)) onclose();
  }
</script>

<Sheet title={isNew ? "Nouvelle catégorie" : "Modifier la catégorie"} {onclose} width={460}>
  <div class="row">
    <CategoryBadge icon={draft.icon} colorIndex={draft.colorIndex} size={40} />
    <!-- svelte-ignore a11y_autofocus -->
    <input class="field grow" placeholder="Nom" aria-label="Nom" bind:value={draft.label} autofocus
           onkeydown={(e) => { if (e.key === "Enter") save(); }} />
  </div>
  {#if isNew}
    <div class="segmented" role="group" aria-label="Type">
      {#each kinds as k (k)}
        <button type="button" class:selected={draft.kind === k} onclick={() => (draft.kind = k)}>{kindLabel[k]}</button>
      {/each}
    </div>
  {/if}
  {#if draft.kind === "expense"}
    <div class="col tight">
      <input class="field" class:invalid={!budgetIsValid} placeholder="Budget mensuel (facultatif)" aria-label="Budget mensuel"
             inputmode="decimal" bind:value={budgetText} onkeydown={(e) => { if (e.key === "Enter") save(); }} />
      <span class="caption" class:negative={!budgetIsValid}>
        {budgetIsValid ? "Laisse vide pour ne pas fixer de budget." : "Saisis un montant supérieur à 0."}
      </span>
    </div>
  {/if}
  <div class="col tight">
    <span class="caption strong">Icône</span>
    <div class="icons">
      {#each categorySymbols as symbol (symbol)}
        <button type="button" class="icon" class:selected={draft.icon === symbol} aria-label={symbol} onclick={() => (draft.icon = symbol)}>
          <Icon name={symbol} size={18} color={draft.icon === symbol ? "var(--accent)" : "var(--text-secondary)"} />
        </button>
      {/each}
    </div>
  </div>
  <div class="col tight">
    <span class="caption strong">Couleur</span>
    <Swatches value={draft.colorIndex} onselect={(i) => (draft.colorIndex = i)} />
  </div>
  {#if !isNew && !store.isProtected(draft)}
    <button type="button" class="btn danger" onclick={remove}>Supprimer la catégorie</button>
  {/if}
  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .grow { flex: 1; }
  .strong { font-weight: 600; }
  .segmented { align-self: flex-start; }
  .icons { display: grid; grid-template-columns: repeat(auto-fill, minmax(44px, 1fr)); gap: 8px; }
  .icon {
    width: 40px; height: 40px; border: none; border-radius: var(--radius-small); background: var(--surface-secondary);
    display: inline-flex; align-items: center; justify-content: center; padding: 0;
  }
  .icon.selected { background: color-mix(in srgb, var(--accent) 15%, transparent); }
</style>
