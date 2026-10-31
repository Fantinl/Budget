<script lang="ts">
  // Liste des opérations récurrentes (RecurringView.swift), affichée depuis les réglages.
  import { store } from "../../lib/app.svelte";
  import { euros, shortDate } from "../../lib/format";
  import { newID, type RecurringOperation } from "../../lib/model";
  import { deleteRecurring, monthlyAmountCents, nextOccurrence, upsertRecurring } from "../../lib/logic/recurring";
  import { confirmDialog } from "../../lib/platform";
  import Card from "../../ui/Card.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Icon from "../../ui/Icon.svelte";
  import ContextMenu, { type MenuItem } from "../accounts/ContextMenu.svelte";
  import RecurringForm from "./RecurringForm.svelte";

  const weekdayName = new Intl.DateTimeFormat("fr-FR", { weekday: "long" });
  const dayMonth = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "long" });

  let target = $state<{ operation: RecurringOperation; isNew: boolean } | null>(null);
  let menu = $state<{ x: number; y: number; items: MenuItem[] } | null>(null);

  /// « Chaque mois, le 5 » / « Chaque semaine, le lundi » / « Chaque année, le 14 juillet ».
  function scheduleDescription(op: RecurringOperation): string {
    const label = { weekly: "Chaque semaine", monthly: "Chaque mois", quarterly: "Chaque trimestre", yearly: "Chaque année" }[op.frequency];
    switch (op.frequency) {
      case "weekly": return `${label}, le ${weekdayName.format(op.startDate)}`;
      case "monthly": case "quarterly": return `${label}, le ${op.startDate.getDate()}`;
      case "yearly": return `${label}, le ${dayMonth.format(op.startDate)}`;
    }
  }

  const upcoming = $derived(
    store.recurringOperations
      .flatMap(op => {
        const next = op.isActive ? nextOccurrence(op) : null;
        return next ? [{ op, next }] : [];
      })
      .sort((a, b) => a.next.getTime() - b.next.getTime()),
  );

  const inactive = $derived(
    store.recurringOperations
      .filter(op => !op.isActive || nextOccurrence(op) === null)
      .sort((a, b) => a.name.localeCompare(b.name, "fr", { sensitivity: "base" })),
  );

  const monthlyTotal = (kind: "expense" | "income") =>
    Math.round(upcoming.filter(u => u.op.kind === kind).reduce((sum, u) => sum + monthlyAmountCents(u.op), 0));

  const statusText = (op: RecurringOperation, next: Date | null) => (next ? `Prochaine : ${shortDate(next)}` : op.isActive ? "Terminée" : "En pause");

  async function askDelete(op: RecurringOperation) {
    if (await confirmDialog("Les opérations déjà créées sont conservées.", { title: "Supprimer cette récurrente ?", okLabel: "Supprimer" })) {
      deleteRecurring(store, op);
    }
  }

  function items(op: RecurringOperation): MenuItem[] {
    return [
      { label: "Modifier", icon: "pencil", action: () => (target = { operation: op, isNew: false }) },
      { label: op.isActive ? "Mettre en pause" : "Réactiver", icon: op.isActive ? "pause.circle" : "play.circle",
        action: () => upsertRecurring(store, { ...op, isActive: !op.isActive }) },
      { label: "Supprimer", icon: "trash", danger: true, action: () => { void askDelete(op); } },
    ];
  }

  function openMenu(e: MouseEvent, op: RecurringOperation) {
    e.preventDefault();
    menu = { x: e.clientX, y: e.clientY, items: items(op) };
  }

  function menuFromButton(e: MouseEvent, op: RecurringOperation) {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    menu = { x: r.left, y: r.bottom + 4, items: items(op) };
  }

  function addNew() {
    target = {
      isNew: true,
      operation: { id: newID(), name: "", amountCents: 0, kind: "expense", categoryID: store.categoriesFor("expense")[0]?.id ?? "",
                   accountID: null, note: "", frequency: "monthly", startDate: new Date(), endDate: null, isActive: true,
                   lastGeneratedDate: null },
    };
  }
</script>

{#snippet row(op: RecurringOperation, next: Date | null, dimmed: boolean)}
  {@const category = store.category(op.categoryID)}
  <div class="cell">
    <button type="button" class="open" onclick={() => (target = { operation: op, isNew: false })} oncontextmenu={(e) => openMenu(e, op)}>
      <Card>
        <div class="row" class:dimmed>
          <CategoryBadge icon={category.icon} colorIndex={category.colorIndex} />
          <div class="col tight info">
            <span class="truncate">{op.name}</span>
            <span class="caption">{scheduleDescription(op)}</span>
            <span class="caption tertiary">{statusText(op, next)}</span>
          </div>
          <span class="amount" class:positive={op.kind === "income"}>{op.kind === "income" ? "+" : ""}{euros(op.amountCents)}</span>
          <span class="more-space"></span>
        </div>
      </Card>
    </button>
    <button type="button" class="more" title="Actions" aria-label="Actions de {op.name}" onclick={(e) => menuFromButton(e, op)}>
      <Icon name="ellipsis" size={14} />
    </button>
  </div>
{/snippet}

<div class="wrap">
  <Card>
    <div class="line summary">
      <div class="col tight">
        <span class="caption">Dépenses / mois</span>
        <span class="amount title">{euros(monthlyTotal("expense"))}</span>
        <span class="caption tertiary">estimation</span>
      </div>
      <div class="col tight right">
        <span class="caption">Revenus / mois</span>
        <span class="amount title positive">+{euros(monthlyTotal("income"))}</span>
        <span class="caption tertiary">estimation</span>
      </div>
    </div>
  </Card>

  {#if store.recurringOperations.length === 0}
    <p class="empty">Aucune opération récurrente. Ajoutez un loyer, un salaire, un abonnement…</p>
  {/if}

  {#each upcoming as u (u.op.id)}{@render row(u.op, u.next, false)}{/each}

  {#if inactive.length > 0}
    <span class="caption paused">En pause ou terminées</span>
    {#each inactive as op (op.id)}{@render row(op, null, true)}{/each}
  {/if}

  <button type="button" class="fab" title="Nouvelle opération récurrente" onclick={addNew}><Icon name="plus" size={15} /> Nouvelle</button>
</div>

{#if menu}<ContextMenu x={menu.x} y={menu.y} items={menu.items} onclose={() => (menu = null)} />{/if}
{#if target}<RecurringForm operation={target.operation} isNew={target.isNew} onclose={() => (target = null)} />{/if}

<style>
  .wrap { display: flex; flex-direction: column; gap: var(--spacing); padding: var(--padding); }
  .summary { align-items: flex-start; }
  .right { text-align: right; }
  .info { flex: 1; min-width: 0; }
  .dimmed { opacity: 0.5; }
  .paused { padding-top: var(--spacing); }
  .cell { position: relative; }
  .open { display: block; width: 100%; padding: 0; border: none; background: none; color: inherit; font: inherit; text-align: left; border-radius: var(--radius); }
  .more-space { width: 22px; flex-shrink: 0; }
  .more {
    position: absolute; top: 50%; right: 8px; transform: translateY(-50%); width: 22px; height: 22px; display: inline-flex;
    align-items: center; justify-content: center; border: none; border-radius: 50%; background: transparent;
    color: var(--text-secondary); opacity: 0;
  }
  .cell:hover .more, .more:focus-visible { opacity: 1; }
  .more:hover { background: var(--surface-secondary); }
  .fab {
    position: sticky; bottom: var(--padding); align-self: flex-end; display: inline-flex; align-items: center; gap: 6px;
    padding: var(--spacing) calc(var(--padding) + 4px); border: none; border-radius: 999px; margin-top: var(--spacing);
    background: var(--accent); color: var(--on-accent); font-size: var(--title); font-weight: var(--title-weight);
    box-shadow: 0 4px 10px color-mix(in srgb, var(--accent) 35%, transparent);
  }
  .fab:hover { filter: brightness(1.08); }
</style>
