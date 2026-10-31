<script lang="ts">
  // Champ de saisie express (« café 2,5 hier ») placé en tête de la liste des opérations. Port de ExpressEntryBar.swift.
  import type { Transaction } from "../../lib/model";
  import { store } from "../../lib/app.svelte";
  import { euros, shortDate } from "../../lib/format";
  import { daysBetween } from "../../lib/dates";
  import { guessCategoryID, parse } from "../../lib/logic/expressEntry";
  import { newID } from "../../lib/model";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Icon from "../../ui/Icon.svelte";
  import PopupMenu from "./PopupMenu.svelte";
  import { isMac } from "./keys";

  let { accountID = null, onOpenForm }: {
    /// Compte de la vue courante (null = compte par défaut).
    accountID?: string | null;
    /// Ouvre le formulaire complet pré-rempli (Alt+Entrée ou bouton) ; absent = fonction masquée.
    onOpenForm?: (t: Transaction) => void;
  } = $props();

  let text = $state("");
  /// Catégorie choisie à la main, valable tant que le libellé interprété ne change pas.
  let override = $state<{ label: string; id: string } | null>(null);
  let confirmation = $state<{ id: string; transaction: Transaction } | null>(null);
  let focused = $state(false);
  let input = $state<HTMLInputElement>();
  let menu = $state<{ x: number; y: number } | null>(null);

  /// ⌘E : place le curseur dans le champ.
  export function focus() { input?.focus(); }

  const entry = $derived(parse(text));
  const categoryID = $derived(
    override && override.label === entry.label
      ? override.id
      : guessCategoryID(entry.label, entry.kind, store.categories, store.quickExpenses, store.transactions));
  const trimmed = $derived(text.trim());
  const category = $derived(store.category(categoryID));

  const signed = (cents: number, kind: string) => (kind === "income" ? "+" : "−") + euros(cents);

  function relativeDate(date: Date): string {
    const days = daysBetween(date, new Date());
    switch (days) {
      case 0: return "Aujourd’hui";
      case 1: return "Hier";
      case 2: return "Avant-hier";
      default: return shortDate(date);
    }
  }

  function makeTransaction(): Transaction | null {
    if (entry.amountCents === null) return null;
    return { id: newID(), amountCents: entry.amountCents, kind: entry.kind, categoryID, note: entry.label, date: entry.date,
             accountID: store.accountIDForNewTransaction(accountID), recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null };
  }

  function submit(e: KeyboardEvent) {
    if (e.key !== "Enter") return;
    e.preventDefault();
    if (e.altKey) { openForm(); return; }
    const transaction = makeTransaction();
    if (!transaction) return;
    store.upsert(transaction);
    text = "";
    override = null;
    confirmation = { id: newID(), transaction };
    input?.focus();
  }

  function openForm() {
    const transaction = makeTransaction();
    if (!onOpenForm || !transaction) return;
    text = "";
    override = null;
    onOpenForm(transaction);
  }

  $effect(() => {
    if (!confirmation) return;
    const timer = setTimeout(() => (confirmation = null), 4000);
    return () => clearTimeout(timer);
  });

  function openMenu(e: MouseEvent) {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    menu = { x: r.left, y: r.bottom + 4 };
  }
</script>

<div class="express">
  <div class="field-box" class:focused>
    <span class="spark" class:on={focused}><Icon name="sparkles" size={15} /></span>
    <input bind:this={input} bind:value={text} type="text" placeholder="Saisie express : café 2,5 hier" aria-label="Saisie express"
           autocomplete="off" onfocus={() => (focused = true)} onblur={() => (focused = false)} onkeydown={submit}
           oninput={() => (confirmation = null)} />
    {#if onOpenForm && entry.amountCents !== null}
      <button type="button" class="open-form" title={`Ouvrir le formulaire complet (${isMac ? "⌥↩" : "Alt+Entrée"})`}
              aria-label="Ouvrir le formulaire complet" onclick={openForm}><Icon name="square.and.pencil" size={15} /></button>
    {/if}
  </div>

  {#if confirmation}
    {@const t = confirmation.transaction}
    <div class="info">
      <Icon name="checkmark.circle.fill" size={14} color="var(--positive)" />
      <span class="caption truncate">{t.note.length === 0 ? store.categoryOf(t).label : t.note} · {signed(t.amountCents, t.kind)} ajouté</span>
      <button type="button" class="undo caption" onclick={() => { store.delete(t); confirmation = null; }}>Annuler</button>
    </div>
  {:else if trimmed.length > 0}
    {#if entry.amountCents !== null}
      <div class="info preview">
        <button type="button" class="cat-button" onclick={openMenu}>
          <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} size={Math.round(34 * 0.7)} />
          <span class="caption">{category.label}</span>
          <Icon name="chevron.down" size={11} />
        </button>
        <span class="truncate label">{entry.label.length === 0 ? category.label : entry.label}</span>
        <span class="tertiary">·</span>
        <span class="caption">{relativeDate(entry.date)}</span>
        <span class="spacer"></span>
        <span class="amount" class:positive={entry.kind === "income"}>{signed(entry.amountCents, entry.kind)}</span>
      </div>
    {:else}
      <span class="caption tertiary hint">Indique un montant</span>
    {/if}
  {/if}
</div>

{#if menu}
  <PopupMenu x={menu.x} y={menu.y} onclose={() => (menu = null)}
             items={store.categoriesFor(entry.kind).map(choice => ({
               label: choice.label, icon: choice.icon, onclick: () => (override = { label: entry.label, id: choice.id }),
             }))} />
{/if}

<style>
  .express { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
  .field-box {
    display: flex; align-items: center; gap: var(--spacing); padding: var(--spacing) var(--padding);
    background: var(--surface-secondary); border-radius: var(--radius-small); border: 1px solid var(--separator);
  }
  .field-box.focused { border-color: color-mix(in srgb, var(--accent) 60%, transparent); }
  .spark { color: var(--text-tertiary); display: inline-flex; }
  .spark.on { color: var(--accent); }
  input { flex: 1; min-width: 0; border: none; outline: none; background: transparent; padding: 0; }
  input::placeholder { color: var(--text-tertiary); }
  .open-form { border: none; background: transparent; color: var(--text-secondary); padding: 0; display: inline-flex; }
  .info { display: flex; align-items: center; gap: var(--spacing); padding: 0 var(--spacing); min-width: 0; }
  .preview .label { min-width: 0; }
  .hint { padding: 0 var(--spacing); }
  .undo { border: none; background: transparent; color: var(--accent); font-weight: 600; padding: 0; }
  .cat-button { display: inline-flex; align-items: center; gap: 6px; border: none; background: transparent; color: var(--text-secondary); padding: 0; flex-shrink: 0; }
</style>
