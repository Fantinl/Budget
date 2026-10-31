<script lang="ts">
  // Feuille de création / modification d'une opération récurrente (RecurringFormView.swift).
  import { store } from "../../lib/app.svelte";
  import { addMonths, addDays, fromInputDate, startOfDay, toInputDate } from "../../lib/dates";
  import { amountInput, euros } from "../../lib/format";
  import { type Category, type Frequency, frequencies, frequencyLabel, type Kind, kindLabel, type RecurringOperation } from "../../lib/model";
  import { containsOperator, evaluate, positiveAmount } from "../../lib/logic/amountExpression";
  import { occurrences, upsertRecurring } from "../../lib/logic/recurring";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";
  import Card from "../../ui/Card.svelte";
  import Sheet from "../../ui/Sheet.svelte";

  let { operation: source, isNew, onclose }: { operation: RecurringOperation; isNew: boolean; onclose: () => void } = $props();

  const longDate = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "long", year: "numeric" });

  // svelte-ignore state_referenced_locally
  let operation = $state<RecurringOperation>({ ...source });
  // svelte-ignore state_referenced_locally
  let amountText = $state(isNew ? "" : amountInput(source.amountCents));
  // svelte-ignore state_referenced_locally
  let hasEnd = $state(source.endDate !== null);
  // svelte-ignore state_referenced_locally
  let endDate = $state<Date>(source.endDate ?? addMonths(source.startDate, 12));
  /// Échéances déjà passées (avant aujourd'hui) d'une récurrente jamais générée : on demande quoi en faire.
  let pastOccurrences = $state.raw<Date[]>([]);

  const parsedAmount = $derived(positiveAmount(amountText));
  const isValid = $derived(parsedAmount !== null && operation.name.trim().length > 0);
  const hint = $derived(containsOperator(amountText) ? evaluate(amountText) : undefined);

  /// Comptes sélectionnables, plus celui de la récurrente s'il est Izly (pour ne pas la casser).
  const activeAccounts = $derived(store.accounts.filter(a => !a.isArchived && (a.kind !== "izly" || a.id === operation.accountID)));

  const availableCategories = $derived.by((): Category[] => {
    const visible = store.categoriesFor(operation.kind);
    const current = store.category(operation.categoryID);
    return visible.some(c => c.id === current.id) || current.kind !== operation.kind ? visible : [...visible, current];
  });

  function setKind(kind: Kind) {
    operation.kind = kind;
    if (store.category(operation.categoryID).kind !== kind) operation.categoryID = store.categoriesFor(kind)[0]?.id ?? "";
  }

  function setStart(value: string) {
    const d = fromInputDate(value);
    if (!d) return;
    operation.startDate = d;
    if (hasEnd && endDate.getTime() < d.getTime()) endDate = d;
  }

  function save() {
    if (parsedAmount === null) return;
    operation.amountCents = parsedAmount;
    operation.name = operation.name.trim();
    operation.note = operation.note.trim();
    operation.endDate = hasEnd ? endDate : null;
    if (activeAccounts.length <= 1) operation.accountID = null;
    // Jamais générée et commence dans le passé : demander s'il faut créer les échéances passées.
    if (operation.lastGeneratedDate === null) {
      const yesterday = addDays(startOfDay(new Date()), -1);
      const past = occurrences($state.snapshot(operation) as RecurringOperation, operation.startDate, yesterday);
      if (past.length > 0) { pastOccurrences = past; return; }
    }
    commit(false);
  }

  function commit(skippingPast: boolean) {
    const result = $state.snapshot(operation) as RecurringOperation;
    if (skippingPast) result.lastGeneratedDate = pastOccurrences[pastOccurrences.length - 1] ?? null;
    pastOccurrences = [];
    upsertRecurring(store, result);
    onclose();
  }
</script>

<Sheet title={isNew ? "Nouvelle récurrente" : "Modifier"} {onclose} width={460}>
  <Card><input class="plain" type="text" placeholder="Loyer, salaire…" aria-label="Nom" bind:value={operation.name} /></Card>

  <div class="col tight">
    <div class="amount-line large-amount">
      <input class="amount" type="text" inputmode="decimal" placeholder="0,00" aria-label="Montant" bind:value={amountText} />
      <span class="secondary">€</span>
    </div>
    {#if hint !== undefined}
      {#if hint !== null}<span class="caption nums center">= {euros(hint)}</span>{:else}<span class="caption negative center">Calcul invalide</span>{/if}
    {/if}
  </div>

  <div class="segmented seg-full" role="group" aria-label="Type">
    {#each ["expense", "income"] as const as kind (kind)}
      <button type="button" class:selected={operation.kind === kind} onclick={() => setKind(kind)}>{kindLabel[kind]}</button>
    {/each}
  </div>

  <Card>
    <div class="categories">
      {#each availableCategories as category (category.id)}
        {@const selected = operation.categoryID === category.id}
        <button type="button" class="category" aria-pressed={selected} onclick={() => (operation.categoryID = category.id)}>
          <span class="ring" class:selected><CategoryBadge icon={category.icon} colorIndex={category.colorIndex} /></span>
          <span class="caption truncate" class:primary={selected}>{category.label}</span>
        </button>
      {/each}
    </div>
  </Card>

  <Card>
    <label class="line center"><span>Fréquence</span>
      <select class="field" bind:value={operation.frequency}>
        {#each frequencies as f (f)}<option value={f satisfies Frequency}>{frequencyLabel[f]}</option>{/each}
      </select>
    </label>
    {#if activeAccounts.length > 1}
      <label class="line center"><span>Compte</span>
        <select class="field" value={operation.accountID ?? ""} onchange={(e) => (operation.accountID = e.currentTarget.value === "" ? null : e.currentTarget.value)}>
          <option value="">Compte par défaut</option>
          {#each activeAccounts as a (a.id)}<option value={a.id}>{a.name}</option>{/each}
        </select>
      </label>
    {/if}
  </Card>

  <Card>
    <label class="line center"><span class="caption">Première échéance</span>
      <input class="field" type="date" value={toInputDate(operation.startDate)} onchange={(e) => setStart(e.currentTarget.value)} aria-label="Première échéance" />
    </label>
  </Card>

  <Card>
    <label class="line center"><span>Date de fin</span><input type="checkbox" class="switch" bind:checked={hasEnd} /></label>
    {#if hasEnd}
      <input class="field" type="date" min={toInputDate(operation.startDate)} value={toInputDate(endDate)} aria-label="Fin"
             onchange={(e) => { const d = fromInputDate(e.currentTarget.value); if (d) endDate = d; }} />
    {/if}
    <label class="line center"><span>Active</span><input type="checkbox" class="switch" bind:checked={operation.isActive} /></label>
  </Card>

  <Card><textarea class="plain note" rows="2" placeholder="Facultatif" aria-label="Description" bind:value={operation.note}></textarea></Card>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Annuler</button>
    <button type="button" class="btn primary" disabled={!isValid} onclick={save}>Enregistrer</button>
  {/snippet}
</Sheet>

{#if pastOccurrences.length > 0}
  {@const n = pastOccurrences.length}
  <Sheet title="{n} échéance{n > 1 ? 's sont' : ' est'} déjà passée{n > 1 ? 's' : ''}" onclose={() => (pastOccurrences = [])} width={420}>
    <p class="message">La première échéance ({longDate.format(pastOccurrences[0])}) est dans le passé.</p>
    {#snippet footer()}
      <button type="button" class="btn" onclick={() => (pastOccurrences = [])}>Annuler</button>
      <button type="button" class="btn" onclick={() => commit(true)}>Commencer à partir d’aujourd’hui</button>
      <button type="button" class="btn primary" onclick={() => commit(false)}>Créer aussi les {n} opérations passées</button>
    {/snippet}
  </Sheet>
{/if}

<style>
  .plain { width: 100%; border: none; outline: none; background: transparent; color: var(--text-primary); }
  .note { resize: vertical; font: inherit; }
  .amount-line { display: flex; justify-content: center; align-items: baseline; gap: 4px; padding: var(--spacing) 0; }
  .amount { width: 150px; text-align: right; border: none; outline: none; background: transparent; color: var(--text-primary); font: inherit; }
  .center { align-items: center; }
  .caption.center { text-align: center; }
  .seg-full { display: flex; }
  .seg-full button { flex: 1; }
  .categories { display: grid; grid-template-columns: repeat(auto-fill, minmax(76px, 1fr)); gap: var(--spacing); }
  .category { display: flex; flex-direction: column; align-items: center; gap: 6px; border: none; background: none; min-width: 0; }
  .category .ring { border-radius: 50%; display: inline-flex; outline: 2px solid transparent; outline-offset: 1px; }
  .category .ring.selected { outline-color: var(--accent); }
  .category .primary { color: var(--text-primary); }
  .message { margin: 0; }
</style>
