<script lang="ts">
  // Configuration des dépenses rapides (modèles de dépenses habituelles). Port de SettingsQuickExpenses.swift.
  import { store } from "../../lib/app.svelte";
  import { type QuickExpense, newID } from "../../lib/model";
  import { euros } from "../../lib/format";
  import { moveItems } from "../../lib/logic/accounts";
  import Icon from "../../ui/Icon.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Group from "./Group.svelte";
  import ReorderButtons from "./ReorderButtons.svelte";
  import QuickSheet from "./QuickSheet.svelte";
  import { type ReorderMove, moveDestination } from "./settingsLogic";

  let editing = $state<{ quick: QuickExpense; isNew: boolean } | null>(null);

  function create() {
    editing = { quick: { id: newID(), name: "", amountCents: 0, kind: "expense", categoryID: "", note: "", accountID: null }, isNew: true };
  }

  function move(index: number, movement: ReorderMove) {
    const list = store.quickExpenses;
    store.reorderQuickExpenses(moveItems(list, [index], moveDestination(movement, index, list.length)).map(q => q.id));
  }
</script>

<Group footer={store.quickExpenses.length === 0 ? "Aucun modèle. Ajoutez vos dépenses habituelles pour les saisir en un clic." : undefined}>
  {#each store.quickExpenses as quick, index (quick.id)}
    {@const category = store.category(quick.categoryID)}
    <div class="qrow">
      <ReorderButtons canMoveUp={index > 0} canMoveDown={index < store.quickExpenses.length - 1}
                      onup={() => move(index, "up")} ondown={() => move(index, "down")} />
      <button type="button" class="edit" onclick={() => (editing = { quick, isNew: false })}>
        <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={32} />
        <span class="texts">
          <span class="truncate">{quick.name}</span>
          <span class="caption truncate">{category.label}</span>
        </span>
        <span class="amount" class:positive={quick.kind === "income"}>{euros(quick.amountCents)}</span>
      </button>
      <button type="button" class="icon-btn" title="Supprimer" aria-label="Supprimer" onclick={() => store.deleteQuickExpense(quick)}>
        <Icon name="trash" size={15} />
      </button>
    </div>
  {/each}
  <button type="button" class="add" onclick={create}>
    <Icon name="plus.circle.fill" size={18} color="var(--accent)" />
    <span>Ajouter une dépense rapide</span>
  </button>
</Group>

{#if editing}
  <QuickSheet quick={editing.quick} isNew={editing.isNew} onclose={() => (editing = null)} />
{/if}

<style>
  .qrow { width: 100%; display: flex; align-items: center; gap: var(--spacing); }
  .edit {
    flex: 1; min-width: 0; display: flex; align-items: center; gap: var(--spacing); text-align: left;
    border: none; background: transparent; padding: 0; color: inherit;
  }
  .texts { flex: 1; display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .icon-btn {
    width: 28px; height: 28px; border: none; background: transparent; border-radius: var(--radius-small); color: var(--text-tertiary);
    display: inline-flex; align-items: center; justify-content: center; padding: 0; flex-shrink: 0;
  }
  .icon-btn:hover { background: var(--surface-secondary); color: var(--negative); }
  .add { width: 100%; border: none; background: transparent; color: inherit; text-align: left; display: flex; align-items: center; gap: 8px; }
</style>
