<script lang="ts">
  // Gestion des catégories (dépenses / revenus), avec masquage, réordonnancement et budget. Port de SettingsCategories.swift.
  import { store } from "../../lib/app.svelte";
  import { type Category, type Kind, newID } from "../../lib/model";
  import { budgetEuros } from "../../lib/logic/budgets";
  import { moveItems } from "../../lib/logic/accounts";
  import Icon from "../../ui/Icon.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Group from "./Group.svelte";
  import ReorderButtons from "./ReorderButtons.svelte";
  import CategorySheet from "./CategorySheet.svelte";
  import { confirmDeleteCategory } from "./CategoryDeletion";
  import { type ReorderMove, moveDestination } from "./settingsLogic";

  let editing = $state<{ category: Category; isNew: boolean } | null>(null);

  const kinds: Kind[] = ["expense", "income"];
  const hidden = $derived(store.categories.filter(c => c.isHidden));

  function create(kind: Kind) {
    editing = { category: { id: newID(), label: "", icon: "cart", kind, colorIndex: 0, isHidden: false,
                            monthlyBudgetCents: null, budgetOverridesCents: null, budgetRollover: null }, isNew: true };
  }

  /// Déplace une catégorie parmi les visibles de son type ; l'ordre complet (masquées comprises) est conservé.
  function reorder(category: Category, movement: ReorderMove) {
    const visible = store.categoriesFor(category.kind);
    const index = visible.findIndex(c => c.id === category.id);
    if (index < 0) return;
    const all = store.categoriesFor(category.kind, true);
    const destination = moveDestination(movement, index, visible.length);
    const fullSource = all.findIndex(c => c.id === category.id);
    let fullDestination: number;
    if (destination < visible.length) fullDestination = all.findIndex(c => c.id === visible[destination].id);
    else {
      const last = all.findIndex(c => c.id === visible[visible.length - 1].id);
      fullDestination = last >= 0 ? last + 1 : all.length;
    }
    store.reorderCategories(category.kind, moveItems(all, [fullSource], fullDestination).map(c => c.id));
  }

  function toggleHidden(category: Category) {
    store.upsertCategory({ ...category, isHidden: !category.isHidden });
  }

  const plural = (n: number) => (n === 1 ? "1 opération" : `${n} opérations`);
</script>

<div class="col">
  <p class="caption note">Fixe un budget mensuel sur une catégorie de dépense pour suivre ta consommation dans le résumé du mois.</p>

  {#snippet row(category: Category, visible: Category[] | null)}
    {@const usage = store.usageCount(category)}
    {@const index = visible ? visible.findIndex(c => c.id === category.id) : -1}
    <div class="crow" class:dim={category.isHidden}>
      {#if visible}
        <ReorderButtons canMoveUp={index > 0} canMoveDown={index < visible.length - 1}
                        onup={() => reorder(category, "up")} ondown={() => reorder(category, "down")} />
      {/if}
      <button type="button" class="edit" onclick={() => (editing = { category, isNew: false })}>
        <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={32} />
        <span class="texts">
          <span class="name">
            <span class="truncate">{category.label}</span>
            {#if usage > 0}<Icon name="lock.fill" size={11} color="var(--text-tertiary)" />{/if}
          </span>
          {#if category.kind === "expense" && category.monthlyBudgetCents && category.monthlyBudgetCents > 0}
            <span class="caption tertiary">{budgetEuros(category.monthlyBudgetCents)} / mois</span>
          {/if}
          {#if usage > 0}<span class="caption tertiary">{plural(usage)}</span>{/if}
        </span>
      </button>
      <button type="button" class="icon-btn" title={category.isHidden ? "Réafficher" : "Masquer"}
              aria-label={category.isHidden ? "Réafficher" : "Masquer"} onclick={() => toggleHidden(category)}>
        <Icon name={category.isHidden ? "eye" : "eye.slash"} size={15} />
      </button>
      {#if store.isProtected(category)}
        <span class="caption tertiary default"><Icon name="pin.fill" size={11} /> Par défaut</span>
      {:else}
        <button type="button" class="icon-btn trash" title="Supprimer la catégorie" aria-label="Supprimer la catégorie"
                onclick={() => confirmDeleteCategory(store, category)}>
          <Icon name="trash" size={15} />
        </button>
      {/if}
    </div>
  {/snippet}

  {#each kinds as kind (kind)}
    {@const visible = store.categoriesFor(kind)}
    <Group header={kind === "expense" ? "Dépenses" : "Revenus"}>
      {#each visible as category (category.id)}
        {@render row(category, visible)}
      {/each}
      <button type="button" class="add" onclick={() => create(kind)}>
        <Icon name="plus.circle.fill" size={18} color="var(--accent)" />
        <span>{kind === "expense" ? "Ajouter une catégorie de dépense" : "Ajouter une catégorie de revenu"}</span>
      </button>
    </Group>
  {/each}

  {#if hidden.length > 0}
    <Group header="Masquées">
      {#each hidden as category (category.id)}
        {@render row(category, null)}
      {/each}
    </Group>
  {/if}
</div>

{#if editing}
  <CategorySheet category={editing.category} isNew={editing.isNew} onclose={() => (editing = null)} />
{/if}

<style>
  .note { margin: 0 var(--padding); }
  .crow { width: 100%; display: flex; align-items: center; gap: var(--spacing); }
  .crow.dim { opacity: 0.5; }
  .edit {
    flex: 1; min-width: 0; display: flex; align-items: center; gap: var(--spacing); text-align: left;
    border: none; background: transparent; padding: 0; color: inherit;
  }
  .texts { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .name { display: flex; align-items: center; gap: 4px; min-width: 0; }
  .icon-btn {
    width: 28px; height: 28px; border: none; background: transparent; border-radius: var(--radius-small); color: var(--text-tertiary);
    display: inline-flex; align-items: center; justify-content: center; padding: 0; flex-shrink: 0;
  }
  .icon-btn:hover { background: var(--surface-secondary); color: var(--text-secondary); }
  .icon-btn.trash:hover { color: var(--negative); }
  .default { display: inline-flex; align-items: center; gap: 4px; white-space: nowrap; }
  .add { width: 100%; border: none; background: transparent; color: inherit; text-align: left; display: flex; align-items: center; gap: 8px; }
</style>
