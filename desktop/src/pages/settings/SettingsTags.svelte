<script lang="ts">
  // Gestion des tags : liste réordonnable, ajout, édition (nom, couleur) et suppression. Port de SettingsTags.swift.
  import { store } from "../../lib/app.svelte";
  import { type Tag, newID } from "../../lib/model";
  import { categoryColor } from "../../lib/theme.svelte";
  import { moveTags, tagUsageCount } from "../../lib/logic/tags";
  import Icon from "../../ui/Icon.svelte";
  import Group from "./Group.svelte";
  import ReorderButtons from "./ReorderButtons.svelte";
  import TagSheet from "./TagSheet.svelte";
  import { confirmDeleteTag } from "./TagDeletion";
  import { type ReorderMove, moveDestination } from "./settingsLogic";

  let editing = $state<{ tag: Tag; isNew: boolean } | null>(null);

  function move(index: number, movement: ReorderMove) {
    moveTags(store, [index], moveDestination(movement, index, store.tags.length));
  }

  const usageText = (n: number) => (n === 0 ? "Aucune opération" : n === 1 ? "1 opération" : `${n} opérations`);
</script>

<div class="col">
  <p class="caption note">Les tags complètent la catégorie : #vacances, #remboursable, #cadeau… Une opération peut en avoir plusieurs.</p>
  <Group>
    {#each store.tags as tag, index (tag.id)}
      <div class="trow">
        <ReorderButtons canMoveUp={index > 0} canMoveDown={index < store.tags.length - 1}
                        onup={() => move(index, "up")} ondown={() => move(index, "down")} />
        <button type="button" class="edit" onclick={() => (editing = { tag, isNew: false })}>
          <span class="dot" style:background={categoryColor(tag.colorIndex)}></span>
          <span class="texts">
            <span class="truncate">{tag.name}</span>
            <span class="caption tertiary">{usageText(tagUsageCount(store, tag))}</span>
          </span>
        </button>
        <button type="button" class="icon-btn" title="Supprimer le tag" aria-label="Supprimer le tag" onclick={() => confirmDeleteTag(store, tag)}>
          <Icon name="trash" size={15} />
        </button>
      </div>
    {/each}
    <button type="button" class="add" onclick={() => (editing = { tag: { id: newID(), name: "", colorIndex: 0 }, isNew: true })}>
      <Icon name="plus.circle.fill" size={18} color="var(--accent)" />
      <span>Ajouter un tag</span>
    </button>
  </Group>
</div>

{#if editing}
  <TagSheet tag={editing.tag} isNew={editing.isNew} onclose={() => (editing = null)} />
{/if}

<style>
  .note { margin: 0 var(--padding); }
  .trow { width: 100%; display: flex; align-items: center; gap: var(--spacing); }
  .edit {
    flex: 1; min-width: 0; display: flex; align-items: center; gap: var(--spacing); text-align: left;
    border: none; background: transparent; padding: 0; color: inherit;
  }
  .dot { width: 14px; height: 14px; border-radius: 50%; flex-shrink: 0; }
  .texts { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .icon-btn {
    width: 28px; height: 28px; border: none; background: transparent; border-radius: var(--radius-small); color: var(--text-tertiary);
    display: inline-flex; align-items: center; justify-content: center; padding: 0; flex-shrink: 0;
  }
  .icon-btn:hover { background: var(--surface-secondary); color: var(--negative); }
  .add { width: 100%; border: none; background: transparent; color: inherit; text-align: left; display: flex; align-items: center; gap: 8px; }
</style>
