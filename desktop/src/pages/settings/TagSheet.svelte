<script lang="ts">
  // Création / modification d'un tag (SettingsTagSheet).
  import { store } from "../../lib/app.svelte";
  import type { Tag } from "../../lib/model";
  import { categoryColor } from "../../lib/theme.svelte";
  import { upsertTag } from "../../lib/logic/tags";
  import { confirmDeleteTag } from "./TagDeletion";
  import Sheet from "../../ui/Sheet.svelte";
  import Swatches from "./Swatches.svelte";

  let { tag, isNew, onclose }: { tag: Tag; isNew: boolean; onclose: () => void } = $props();

  // svelte-ignore state_referenced_locally
  let draft = $state<Tag>({ ...tag });
  const canSave = $derived(draft.name.trim() !== "");

  function save() {
    if (!canSave) return;
    upsertTag(store, { ...draft, name: draft.name.trim() });
    onclose();
  }

  async function remove() {
    if (await confirmDeleteTag(store, draft)) onclose();
  }
</script>

<Sheet title={isNew ? "Nouveau tag" : "Modifier le tag"} {onclose} width={440}>
  <div class="row">
    <span class="dot" style:background={categoryColor(draft.colorIndex)}></span>
    <!-- svelte-ignore a11y_autofocus -->
    <input class="field grow" placeholder="Nom" aria-label="Nom" bind:value={draft.name} autofocus
           onkeydown={(e) => { if (e.key === "Enter") save(); }} />
  </div>
  <div class="col tight">
    <span class="caption strong">Couleur</span>
    <Swatches value={draft.colorIndex} onselect={(i) => (draft.colorIndex = i)} />
  </div>
  {#if !isNew}
    <button type="button" class="btn danger" onclick={remove}>Supprimer le tag</button>
  {/if}
  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!canSave} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

<style>
  .grow { flex: 1; }
  .strong { font-weight: 600; }
  .dot { width: 16px; height: 16px; border-radius: 50%; flex-shrink: 0; }
</style>
