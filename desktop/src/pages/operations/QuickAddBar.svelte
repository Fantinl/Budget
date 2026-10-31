<script lang="ts" module>
  import type { Transaction } from "../../lib/model";

  /// Message affiché par le toast après un ajout rapide.
  export interface QuickAddToast { id: string; transaction: Transaction; name: string }
</script>

<script lang="ts">
  // Rangée défilante de pastilles pour ajouter les dépenses habituelles en un clic, et bandeau d'annulation.
  // Port de QuickAddBar.swift. ⌘1…⌘9 : ajout rapide dans l'ordre affiché.
  import { type QuickExpense, MAIN_ACCOUNT_ID, newID } from "../../lib/model";
  import type { Draft } from "../../lib/drafts";
  import { store } from "../../lib/app.svelte";
  import { euros } from "../../lib/format";
  import { startOfMonth } from "../../lib/dates";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import PopupMenu from "./PopupMenu.svelte";
  import { hasMod, isMac, modalOpen } from "./keys";

  let { month = $bindable(), draft = $bindable(), toast = $bindable(), accountID = null }: {
    month: Date;
    draft: Draft | null;
    toast: QuickAddToast | null;
    /// Compte imposé aux ajouts rapides (vue d'un compte) ; null = celui du réglage.
    accountID?: string | null;
  } = $props();

  let menu = $state<{ x: number; y: number; quick: QuickExpense } | null>(null);

  const withAccount = (quick: QuickExpense): QuickExpense =>
    accountID ? { ...quick, accountID: accountID === MAIN_ACCOUNT_ID ? null : accountID } : quick;

  function add(quick: QuickExpense) {
    const q = withAccount(quick);
    const transaction = store.addQuick(q);
    // Revient au mois courant pour que l'ajout soit visible.
    const current = startOfMonth(new Date());
    if (month.getTime() !== current.getTime()) month = current;
    toast = { id: newID(), transaction, name: q.name };
  }

  function addWithChanges(quick: QuickExpense) {
    const q = withAccount(quick);
    draft = { transaction: store.makeTransaction(q), isNew: true };
  }

  function onkeydown(e: KeyboardEvent) {
    if (!hasMod(e) || e.altKey || e.shiftKey || !/^[1-9]$/.test(e.key) || modalOpen()) return;
    const quick = store.quickExpenses[Number(e.key) - 1];
    if (!quick) return;
    e.preventDefault();
    add(quick);
  }
</script>

<svelte:window {onkeydown} />

<div class="quick">
  {#if store.quickExpenses.length === 0}
    <span class="caption tertiary lead">Configure tes dépenses rapides dans les Réglages</span>
  {:else}
    <span class="caption lead">Ajout rapide</span>
    <div class="scroller">
      {#each store.quickExpenses as quick, index (quick.id)}
        {@const category = store.category(quick.categoryID)}
        <button type="button" class="chip" title={index < 9 ? `${isMac ? "⌘" : "Ctrl+"}${index + 1}` : undefined}
                onclick={() => add(quick)}
                oncontextmenu={(e) => { e.preventDefault(); menu = { x: e.clientX, y: e.clientY, quick }; }}>
          <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={Math.round(34 * 0.7)} />
          <span class="name truncate">{quick.name}</span>
          <span class="caption nums" class:positive={quick.kind === "income"}>{euros(quick.amountCents)}</span>
        </button>
      {/each}
    </div>
  {/if}
</div>

{#if menu}
  {@const target = menu.quick}
  <PopupMenu x={menu.x} y={menu.y} onclose={() => (menu = null)}
             items={[{ label: "Ajouter avec modifications…", icon: "square.and.pencil", onclick: () => addWithChanges(target) }]} />
{/if}

<style>
  .quick { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
  .lead { padding-left: 6px; }
  .scroller { display: flex; gap: var(--spacing); overflow-x: auto; padding: 2px; scrollbar-width: none; }
  .scroller::-webkit-scrollbar { display: none; }
  .chip {
    display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; border: none; color: var(--text-primary);
    padding: 6px var(--spacing) 6px 6px; border-radius: 999px; background: var(--surface);
  }
  .chip:hover { filter: brightness(0.97); }
  .name { max-width: 160px; }
</style>
