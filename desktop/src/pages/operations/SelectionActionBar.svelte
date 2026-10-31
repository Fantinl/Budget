<script lang="ts">
  // Barre d'actions flottante affichée quand des opérations sont sélectionnées. Port de SelectionActionBar.swift.
  import { type Account, type Category, type Kind, type Transaction, isTransfer, kindLabel } from "../../lib/model";
  import { store } from "../../lib/app.svelte";
  import { addTagTo, removeAllTags, removeTagFrom, tagState } from "../../lib/logic/bulk";
  import { addTag } from "../../lib/logic/tags";
  import Icon from "../../ui/Icon.svelte";
  import Sheet from "../../ui/Sheet.svelte";
  import PopupMenu, { type MenuItem } from "./PopupMenu.svelte";

  let { selected, oncategory, onaccount, onedit, onduplicate, ondelete, onclose }: {
    selected: Transaction[];
    oncategory: (c: Category) => void;
    onaccount: (a: Account) => void;
    onedit: () => void;
    onduplicate: () => void;
    ondelete: () => void;
    onclose: () => void;
  } = $props();

  let menu = $state<{ x: number; y: number; items: MenuItem[] } | null>(null);
  let showNewTag = $state(false);
  let newTagName = $state("");

  const ids = $derived(new Set(selected.map(t => t.id)));
  const editable = $derived(selected.filter(t => !isTransfer(t)));
  const kinds = $derived((["expense", "income"] as Kind[]).filter(k => editable.some(t => t.kind === k)));

  /// Précision affichée sous la barre quand certaines opérations seront ignorées.
  const hint = $derived.by(() => {
    const parts: string[] = [];
    if (selected.some(isTransfer)) parts.push("Les virements sont ignorés");
    if (kinds.length > 1) parts.push("Catégorie appliquée selon le type (dépense / revenu)");
    return parts.length === 0 ? null : parts.join(" · ");
  });

  function open(e: MouseEvent, items: MenuItem[]) {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    menu = { x: r.left, y: r.top - 6, items };
  }

  function categoryMenu(e: MouseEvent) {
    const items: MenuItem[] = [];
    for (const kind of kinds) {
      items.push({ header: true, label: kindLabel[kind] });
      for (const c of store.categoriesFor(kind)) items.push({ label: c.label, icon: c.icon, onclick: () => oncategory(c) });
    }
    open(e, items);
  }

  const accountMenu = (e: MouseEvent) =>
    open(e, store.selectableAccounts.map(a => ({ label: a.name, onclick: () => onaccount(a) })));

  function tagsMenu(e: MouseEvent) {
    const items: MenuItem[] = store.tags.map(tag => {
      const state = tagState(store, tag.id, ids);
      return { label: tag.name, icon: state === "all" ? "checkmark" : state === "some" ? "minus" : "circle",
               // Ajoute le tag partout, sauf si toutes les opérations l'ont déjà : il est alors retiré.
               onclick: () => (state === "all" ? removeTagFrom(store, tag.id, ids) : addTagTo(store, tag.id, ids)) };
    });
    if (store.tags.length > 0) items.push({ divider: true });
    items.push({ label: "Nouveau tag…", icon: "plus", onclick: () => { newTagName = ""; showNewTag = true; } });
    items.push({ label: "Retirer tous les tags", icon: "tag.slash", onclick: () => removeAllTags(store, ids) });
    open(e, items);
  }

  function createTag() {
    showNewTag = false;
    if (newTagName.trim().length === 0) return;
    addTagTo(store, addTag(store, newTagName).id, ids);
  }
</script>

<div class="wrap">
  {#if hint}<span class="caption">{hint}</span>{/if}
  <div class="bar">
    <span class="title count">{selected.length} sélectionnée{selected.length > 1 ? "s" : ""}</span>
    <span class="divider"></span>
    <button type="button" class="action" disabled={editable.length === 0} onclick={categoryMenu}><Icon name="tag" size={14} />Catégorie</button>
    <button type="button" class="action" disabled={editable.length === 0} onclick={accountMenu}><Icon name="building.columns" size={14} />Compte</button>
    <button type="button" class="action" onclick={tagsMenu}><Icon name="number" size={14} />Tags</button>
    <button type="button" class="action" disabled={editable.length === 0} onclick={onedit}><Icon name="pencil" size={14} />Modifier…</button>
    <button type="button" class="action" disabled={editable.length === 0} onclick={onduplicate}><Icon name="plus.square.on.square" size={14} />Dupliquer</button>
    <button type="button" class="action danger" onclick={ondelete}><Icon name="trash" size={14} />Supprimer</button>
    <button type="button" class="action" title="Désélectionner" aria-label="Désélectionner" onclick={onclose}><Icon name="xmark" size={14} /></button>
  </div>
</div>

{#if menu}
  <PopupMenu x={menu.x} y={menu.y} above items={menu.items} onclose={() => (menu = null)} />
{/if}

{#if showNewTag}
  <Sheet title="Nouveau tag" width={340} onclose={() => (showNewTag = false)}>
    <!-- svelte-ignore a11y_autofocus -->
    <input class="field" type="text" placeholder="Nom du tag" aria-label="Nom du tag" bind:value={newTagName} autofocus
           onkeydown={(e) => { if (e.key === "Enter") { e.preventDefault(); createTag(); } }} />
    {#snippet footer()}
      <button type="button" class="btn" onclick={() => (showNewTag = false)}>Annuler</button>
      <button type="button" class="btn primary" onclick={createTag}>Ajouter</button>
    {/snippet}
  </Sheet>
{/if}

<style>
  .wrap { display: flex; flex-direction: column; align-items: center; gap: 4px; max-width: 640px; width: 100%; margin: 0 auto; pointer-events: auto; }
  .bar {
    display: flex; align-items: center; gap: var(--spacing); max-width: 100%; overflow-x: auto; scrollbar-width: none;
    padding: var(--spacing) var(--padding); border-radius: 999px; background: var(--surface);
    border: var(--card-border-width) solid var(--card-border); box-shadow: 0 4px 18px rgba(0, 0, 0, 0.16), var(--card-shadow);
  }
  .bar::-webkit-scrollbar { display: none; }
  .count { white-space: nowrap; }
  .divider { width: 1px; height: 20px; background: var(--separator); flex-shrink: 0; }
  .action {
    display: inline-flex; align-items: center; gap: 5px; flex-shrink: 0; border: none; background: transparent;
    color: var(--text-primary); padding: 4px 6px; border-radius: var(--radius-small); white-space: nowrap;
  }
  .action:hover:not(:disabled) { background: var(--surface-secondary); }
  .action:disabled { opacity: 0.4; }
  .action.danger { color: var(--negative); }
</style>
