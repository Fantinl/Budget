<!-- Import d'un relevé bancaire (CSV, Excel, OFX) : port de ImportStatementView.swift.
     Choix du fichier, aperçu corrigeable (colonnes, catégories, recharges Izly), import en une fois. -->
<script lang="ts">
  import { untrack } from "svelte";
  import { store } from "../../lib/app.svelte";
  import { type Kind, type Transaction, MAIN_ACCOUNT_ID, newID } from "../../lib/model";
  import { BudgetStore } from "../../lib/store.svelte";
  import { basename, chooseFile, readBytes } from "../../lib/platform";
  import { euros, mediumDate } from "../../lib/format";
  import { addImported, consumeDuplicate, duplicateIndex, isRechargeLabel, type DuplicateIndex, type ImportRecharge } from "../../lib/logic/import";
  import { StatementCategorizer } from "../../lib/statement/categorizer";
  import {
    type StatementColumns, type StatementRow, type StatementTable, StatementError, emptyColumns, isSplit, parseStatement, rowAmount,
    rowKind, rowsFromTable,
  } from "../../lib/statement/parser";
  import Sheet from "../../ui/Sheet.svelte";
  import Icon from "../../ui/Icon.svelte";
  import CategoryBadge from "../../ui/CategoryBadge.svelte";

  let { path = null, onclose }: { path?: string | null; onclose: () => void } = $props();

  /// Ligne de l'aperçu, modifiable par l'utilisateur.
  interface Item {
    key: number;
    row: StatementRow;
    categoryID: string;
    isSelected: boolean;
    isDuplicate: boolean;
    /// Compte Izly de destination si la ligne est une recharge (virement), null sinon.
    izlyAccountID: string | null;
  }

  const EXTENSIONS = ["csv", "tsv", "txt", "ofx", "qfx", "xlsx", "xls"];

  let fileName = $state<string | null>(null);
  let errorText = $state<string | null>(null);
  let table = $state.raw<StatementTable | null>(null);
  let columns = $state<StatementColumns>(emptyColumns());
  let split = $state(false);
  let skipped = $state(0);
  let items = $state.raw<Item[]>([]);
  let hasContent = $state(false);
  let nextKey = 0;

  const activeAccounts = $derived(store.accounts.filter(a => !a.isArchived));
  // Compte par défaut à l'ouverture (remplacé par le premier compte actif s'il n'est pas disponible).
  let accountID = $state(untrack(() => {
    const id = store.defaultAccount.id;
    return store.accounts.some(a => a.id === id && !a.isArchived) ? id : (store.accounts.find(a => !a.isArchived)?.id ?? id);
  }));
  const izlyAccounts = $derived(store.accounts.filter(a => a.kind === "izly" && !a.isArchived && a.id !== accountID));
  const duplicateCount = $derived(items.filter(i => i.isDuplicate).length);
  const rechargeCount = $derived(items.filter(i => i.izlyAccountID !== null).length);
  const selectedCount = $derived(items.filter(i => i.isSelected).length);

  const plural = (n: number, word: string) => `${n} ${word}${n > 1 ? "s" : ""}`;
  const summary = $derived.by(() => {
    let count = plural(items.length, "opération");
    if (rechargeCount > 0) count += ` dont ${plural(rechargeCount, "recharge")} Izly`;
    const parts = [count];
    if (duplicateCount > 0) parts.push(`${duplicateCount} déjà présente${duplicateCount > 1 ? "s" : ""}`);
    if (skipped > 0) parts.push(`${skipped} ligne${skipped > 1 ? "s" : ""} ignorée${skipped > 1 ? "s" : ""}`);
    return parts.join(", ");
  });

  // MARK: Logique

  async function pick() {
    const chosen = await chooseFile([{ name: "Relevés bancaires", extensions: EXTENSIONS }], "Choisir un relevé");
    if (chosen) await load(chosen);
  }

  async function load(file: string) {
    try {
      const buffer = await readBytes(file);
      const content = await parseStatement(new Uint8Array(buffer));
      fileName = basename(file);
      errorText = null;
      if ("table" in content) {
        table = content.table;
        columns = { ...content.table.columns };
        split = isSplit(content.table.columns);
        hasContent = true;
        rebuildItems();
      } else {
        table = null;
        skipped = content.result.skipped;
        hasContent = true;
        items = makeItems(content.result.rows);
      }
    } catch (e) {
      errorText = e instanceof StatementError ? e.message : "Impossible de lire ce fichier.";
    }
  }

  $effect(() => {
    if (path) untrack(() => { void load(path); });
  });

  function rebuildItems() {
    if (!table) return;
    const used: StatementColumns = { ...columns };
    if (split) used.amount = null; else { used.debit = null; used.credit = null; }
    const parsed = rowsFromTable(table, used);
    skipped = parsed.skipped;
    items = makeItems(parsed.rows);
  }

  function makeItems(rows: StatementRow[]): Item[] {
    const categorizer = new StatementCategorizer(store.categories, store.transactions);
    const index = duplicateIndex(store);
    return rows.map(row => {
      const kind = rowKind(row);
      const duplicate = consume(row, index);
      const recharge = kind === "expense" && isRechargeLabel(row.label);
      return { key: nextKey++, row, categoryID: categorizer.suggest(row.label, kind), isSelected: !duplicate, isDuplicate: duplicate,
               izlyAccountID: recharge ? (izlyAccounts[0]?.id ?? null) : null };
    });
  }

  /// Même jour, type, montant et compte (chaque opération existante ne compte qu'une fois), ou même libellé le même jour.
  function consume(row: StatementRow, index: DuplicateIndex): boolean {
    return consumeDuplicate(index, row.date, rowKind(row), rowAmount(row), row.label, accountID);
  }

  function refreshDuplicates() {
    const index = duplicateIndex(store);
    items = items.map(item => {
      const duplicate = consume(item.row, index);
      // Le compte Izly ne peut pas être le compte importé.
      const izly = item.izlyAccountID !== null && item.izlyAccountID === accountID ? (izlyAccounts[0]?.id ?? null) : item.izlyAccountID;
      return { ...item, isDuplicate: duplicate, isSelected: !duplicate, izlyAccountID: izly };
    });
  }

  const update = (key: number, change: Partial<Item>) => { items = items.map(i => (i.key === key ? { ...i, ...change } : i)); };

  function setColumn(field: keyof StatementColumns, value: string) {
    columns = { ...columns, [field]: value === "" ? null : Number(value) };
    rebuildItems();
  }

  function setSplit(value: boolean) {
    split = value;
    rebuildItems();
  }

  function onType(item: Item, value: string) {
    if (value === "normal") update(item.key, { izlyAccountID: null });
    else if (value.startsWith("izly:")) update(item.key, { izlyAccountID: value.slice(5) });
    else update(item.key, { izlyAccountID: null, categoryID: value.slice(4) });
  }

  function runImport() {
    const target = BudgetStore.storedAccountID(accountID);
    const selected = items.filter(i => i.isSelected);
    const imported: Transaction[] = selected.filter(i => i.izlyAccountID === null).map(i => ({
      id: newID(), amountCents: rowAmount(i.row), kind: rowKind(i.row), categoryID: i.categoryID, note: i.row.label, date: i.row.date,
      accountID: target, recurringID: null, transferID: null, tagIDs: null, isAutoMeal: null,
    }));
    const recharges: ImportRecharge[] = selected.filter(i => i.izlyAccountID !== null).map(i => ({
      amountCents: rowAmount(i.row), date: i.row.date, note: i.row.label, izlyAccountID: i.izlyAccountID as string,
    }));
    addImported(store, imported, recharges, accountID);
    onclose();
  }

  const headerLabel = (h: string, i: number) => (h === "" ? `Colonne ${i + 1}` : h);
  const kindCategories = (kind: Kind) => store.categoriesFor(kind);
  void MAIN_ACCOUNT_ID;
</script>

{#snippet columnMenu(title: string, field: "date" | "label" | "debit" | "credit" | "amount", optional: boolean)}
  <div class="line">
    <span>{title}</span>
    <select class="field" value={columns[field] === null ? "" : String(columns[field])} onchange={(e) => setColumn(field, e.currentTarget.value)}>
      {#if optional || columns[field] === null}<option value="">Aucune</option>{/if}
      {#each table?.headers ?? [] as header, index (index)}<option value={String(index)}>{headerLabel(header, index)}</option>{/each}
    </select>
  </div>
{/snippet}

<Sheet title="Importer un relevé" {onclose} width={680}>
  {#if !hasContent}
    <div class="pick col">
      <Icon name="doc.text.magnifyingglass" size={34} color="var(--text-tertiary)" strokeWidth={1.5} />
      <p class="secondary">Exporte ton relevé depuis le site de ta banque en CSV, Excel ou OFX, puis choisis le fichier ici.</p>
      <button class="btn primary" onclick={pick}>Choisir un fichier…</button>
      {#if errorText}<p class="caption negative">{errorText}</p>{/if}
    </div>
  {:else}
    <div class="card col">
      {#if fileName}<span class="caption file"><Icon name="doc.text" size={12} />{fileName}</span>{/if}
      <div class="line">
        <span>Compte</span>
        {#if activeAccounts.length > 1}
          <select class="field" value={accountID} onchange={(e) => { accountID = e.currentTarget.value; refreshDuplicates(); }}>
            {#each activeAccounts as account (account.id)}<option value={account.id}>{account.name}</option>{/each}
          </select>
        {:else}
          <span class="secondary">{activeAccounts[0]?.name ?? store.account(MAIN_ACCOUNT_ID).name}</span>
        {/if}
      </div>

      {#if table}
        <hr class="separator" />
        {@render columnMenu("Date", "date", false)}
        {@render columnMenu("Libellé", "label", true)}
        <div class="segmented seg" role="radiogroup" aria-label="Montant">
          <button type="button" class:selected={!split} onclick={() => setSplit(false)}>Montant unique</button>
          <button type="button" class:selected={split} onclick={() => setSplit(true)}>Débit et crédit</button>
        </div>
        {#if split}
          {@render columnMenu("Débit", "debit", true)}
          {@render columnMenu("Crédit", "credit", true)}
        {:else}
          {@render columnMenu("Montant", "amount", false)}
        {/if}
      {/if}

      <span class="caption">{summary}</span>
      <button class="link caption" onclick={pick}>Choisir un autre fichier…</button>
      {#if errorText}<p class="caption negative">{errorText}</p>{/if}
    </div>

    {#if items.length === 0}
      <p class="secondary empty-note">Aucune opération lisible avec ces colonnes.</p>
    {:else}
      <div class="card list">
        {#each items as item, n (item.key)}
          {@const kind = rowKind(item.row)}
          {#if n > 0}<hr class="separator" />{/if}
          <div class="item" class:off={!item.isSelected}>
            <button class="check" aria-label={item.isSelected ? "Ne pas importer" : "Importer"} onclick={() => update(item.key, { isSelected: !item.isSelected })}>
              <Icon name={item.isSelected ? "checkmark.circle.fill" : "circle"} size={18} color={item.isSelected ? "var(--accent)" : "var(--text-tertiary)"} />
            </button>
            <div class="grow">
              <div class="truncate">{item.row.label}</div>
              <div class="row tight">
                <span class="caption">{mediumDate(item.row.date)}</span>
                {#if item.isDuplicate}<span class="caption chip">déjà présente</span>{/if}
              </div>
            </div>
            <label class="kind">
              {#if item.izlyAccountID}
                <span class="recharge"><Icon name="arrow.left.arrow.right" size={12} />→ {store.account(item.izlyAccountID).name}</span>
              {:else}
                <CategoryBadge icon={store.category(item.categoryID).icon} colorIndex={store.category(item.categoryID).colorIndex} size={26} />
              {/if}
              <select class="hidden-select" aria-label="Catégorie" value={item.izlyAccountID ? `izly:${item.izlyAccountID}` : `cat:${item.categoryID}`}
                      onchange={(e) => onType(item, e.currentTarget.value)}>
                {#if kind === "expense" && izlyAccounts.length > 0}
                  <optgroup label="Type">
                    <option value="normal">Dépense normale</option>
                    {#each izlyAccounts as izly (izly.id)}
                      <option value={`izly:${izly.id}`}>{izlyAccounts.length > 1 ? `Recharge Izly : ${izly.name}` : "Recharge Izly"}</option>
                    {/each}
                  </optgroup>
                {/if}
                <optgroup label="Catégorie" hidden={item.izlyAccountID !== null} disabled={item.izlyAccountID !== null}>
                  {#each kindCategories(kind) as category (category.id)}<option value={`cat:${category.id}`}>{category.label}</option>{/each}
                  {#if !kindCategories(kind).some(c => c.id === item.categoryID)}
                    <option value={`cat:${item.categoryID}`}>{store.category(item.categoryID).label}</option>
                  {/if}
                </optgroup>
              </select>
            </label>
            <span class="amount amt" class:positive={kind === "income"}>{euros(item.row.signedCents)}</span>
          </div>
        {/each}
      </div>
    {/if}
  {/if}


  {#snippet footer()}
    <button class="btn" onclick={onclose}>Annuler</button>
    <button class="btn primary" disabled={selectedCount === 0} onclick={runImport}>
      {selectedCount === 0 ? "Importer" : `Importer ${selectedCount} opération${selectedCount > 1 ? "s" : ""}`}
    </button>
  {/snippet}
</Sheet>

<style>
  .pick { align-items: center; text-align: center; max-width: 420px; margin: 0 auto; padding: calc(var(--padding) * 2) 0; }
  .card { background: var(--surface); border-radius: var(--radius); border: var(--card-border-width) solid var(--card-border); padding: var(--padding); }
  .card.list { padding: 0; }
  .file { display: inline-flex; align-items: center; gap: 4px; }
  .seg { align-self: stretch; }
  .seg button { flex: 1; }
  .link { background: none; border: none; padding: 0; color: var(--accent); text-align: left; align-self: flex-start; }
  .empty-note { padding: var(--padding); text-align: center; }
  .item { display: flex; align-items: center; gap: var(--spacing); padding: var(--spacing) var(--padding); }
  .item.off { opacity: 0.55; }
  .grow { flex: 1; min-width: 0; }
  .check { background: none; border: none; padding: 0; display: inline-flex; }
  .chip { background: var(--surface-secondary); border-radius: var(--radius-small); padding: 0 6px; }
  .kind { position: relative; display: inline-flex; align-items: center; }
  .recharge { display: inline-flex; align-items: center; gap: 4px; font-size: var(--caption); color: var(--accent); background: var(--surface-secondary);
              border-radius: var(--radius-small); padding: 4px var(--spacing); }
  .hidden-select { position: absolute; inset: 0; width: 100%; height: 100%; opacity: 0; }
  .amt { min-width: 90px; text-align: right; }
</style>
