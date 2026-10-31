<script lang="ts">
  // Sélecteur de période : titre cliquable (menu) encadré de flèches précédent / suivant (MonthPicker.swift).
  // `mode` = « month » (par défaut) ou « year » ; `monthsWithData` = débuts de mois ayant des opérations
  // (un point sous les mois / années concernés).
  import Icon from "./Icon.svelte";
  import { addMonths, startOfMonth, startOfYear } from "../lib/dates";
  import { monthAbbrev, monthTitle } from "../lib/format";

  let { month = $bindable(), mode = "month", monthsWithData = [] }: {
    month: Date;
    mode?: "month" | "year";
    monthsWithData?: Iterable<Date>;
  } = $props();

  let open = $state(false);
  let shownYear = $state(0);
  let root: HTMLElement | undefined = $state();

  const step = $derived(mode === "month" ? 1 : 12);
  const currentStart = $derived(mode === "month" ? startOfMonth(new Date()) : startOfYear(new Date()));
  const title = $derived(mode === "month" ? monthTitle(month) : String(month.getFullYear()));
  const nextDisabled = $derived(addMonths(month, step).getTime() > currentStart.getTime());

  const index = (d: Date) => d.getFullYear() * 12 + d.getMonth();
  const dataKeys = $derived(new Set([...monthsWithData].map(index)));
  const currentYear = new Date().getFullYear();
  const currentMonthStart = startOfMonth(new Date());

  /// Années disponibles : de la plus ancienne ayant des données jusqu'à l'année courante.
  const years = $derived.by(() => {
    let oldest = currentYear;
    for (const key of dataKeys) oldest = Math.min(oldest, Math.floor(key / 12));
    const first = Math.min(oldest, month.getFullYear(), currentYear);
    return Array.from({ length: currentYear - first + 1 }, (_, i) => first + i);
  });

  function toggle() {
    if (!open) shownYear = month.getFullYear();
    open = !open;
  }

  function choose(d: Date) {
    month = d;
    open = false;
  }

  const hasDataInYear = (y: number) => {
    for (const key of dataKeys) if (Math.floor(key / 12) === y) return true;
    return false;
  };

  function onwindowdown(e: MouseEvent) {
    if (open && root && !root.contains(e.target as Node)) open = false;
  }
  function onkeydown(e: KeyboardEvent) {
    if (open && e.key === "Escape") { e.stopPropagation(); open = false; }
  }
</script>

<svelte:window onmousedown={onwindowdown} {onkeydown} />

<div class="picker" bind:this={root}>
  <button type="button" class="arrow" aria-label="Précédent" onclick={() => (month = addMonths(month, -step))}>
    <Icon name="chevron.left" size={15} />
  </button>

  <div class="center">
    <button type="button" class="title-button" aria-label={`Choisir la période, ${title}`} aria-expanded={open} onclick={toggle}>
      <span class="title">{title}</span>
      <Icon name="chevron.down" size={12} color="var(--text-secondary)" />
    </button>

    {#if open}
      <div class="popover" role="dialog" aria-label="Choisir la période">
        {#if mode === "month"}
          <div class="year-nav">
            <button type="button" class="arrow small" aria-label="Année précédente" onclick={() => (shownYear -= 1)}>
              <Icon name="chevron.left" size={14} />
            </button>
            <span class="title year">{shownYear}</span>
            <button type="button" class="arrow small" aria-label="Année suivante" disabled={shownYear >= currentYear} onclick={() => (shownYear += 1)}>
              <Icon name="chevron.right" size={14} />
            </button>
          </div>
          <div class="cells">
            {#each Array.from({ length: 12 }, (_, i) => i) as m (m)}
              {@const d = new Date(shownYear, m, 1)}
              {@const selected = index(d) === index(month)}
              {@const future = d.getTime() > currentMonthStart.getTime()}
              <button type="button" class="cell" class:selected class:current={d.getTime() === currentMonthStart.getTime() && !selected}
                      class:future disabled={future} onclick={() => choose(d)}>
                <span>{monthAbbrev(d)}</span>
                <i class="dot" class:on={dataKeys.has(index(d))}></i>
              </button>
            {/each}
          </div>
        {:else}
          <div class="cells">
            {#each years as y (y)}
              {@const selected = month.getFullYear() === y}
              <button type="button" class="cell" class:selected class:current={y === currentYear && !selected}
                      class:future={y > currentYear} disabled={y > currentYear} onclick={() => choose(new Date(y, 0, 1))}>
                <span>{y}</span>
                <i class="dot" class:on={hasDataInYear(y)}></i>
              </button>
            {/each}
          </div>
        {/if}
        <button type="button" class="today" onclick={() => choose(mode === "month" ? currentMonthStart : new Date(currentYear, 0, 1))}>
          Ce mois-ci
        </button>
      </div>
    {/if}
  </div>

  <button type="button" class="arrow" aria-label="Suivant" disabled={nextDisabled} onclick={() => (month = addMonths(month, step))}>
    <Icon name="chevron.right" size={15} />
  </button>
</div>

<style>
  .picker { display: flex; align-items: center; justify-content: center; gap: var(--spacing); }
  .center { position: relative; }
  .arrow {
    width: var(--icon-size); height: var(--icon-size); display: inline-flex; align-items: center; justify-content: center;
    border: none; background: transparent; color: var(--accent); border-radius: var(--radius-small); padding: 0;
  }
  .arrow:hover:not(:disabled) { background: var(--surface-secondary); }
  .arrow:disabled { color: var(--text-tertiary); }
  .arrow.small { width: 28px; height: 28px; }
  .title-button {
    display: inline-flex; align-items: center; gap: 6px; border: none; background: transparent; color: var(--text-primary);
    padding: calc(var(--spacing) / 2) var(--spacing); border-radius: var(--radius-small);
  }
  .title-button:hover { background: var(--surface-secondary); }
  .title { font-size: var(--title); font-weight: var(--title-weight); }
  .popover {
    position: absolute; top: calc(100% + 6px); left: 50%; transform: translateX(-50%); z-index: 50; width: 260px;
    padding: var(--padding); display: flex; flex-direction: column; gap: var(--spacing);
    background: var(--background); border-radius: var(--radius);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.22), 0 0 0 1px var(--separator);
  }
  .year-nav { display: flex; align-items: center; }
  .year { flex: 1; text-align: center; }
  .cells { display: grid; grid-template-columns: repeat(3, 1fr); gap: calc(var(--spacing) / 2); }
  .cell {
    display: flex; flex-direction: column; align-items: center; gap: 3px; padding: calc(var(--spacing) / 2) 0;
    border: 1px solid transparent; background: transparent; color: var(--text-primary); border-radius: var(--radius-small);
  }
  .cell:hover:not(:disabled):not(.selected) { background: var(--surface-secondary); }
  .cell.future { color: var(--text-tertiary); }
  .cell.current { border-color: var(--accent); }
  .cell.selected { background: var(--accent); color: var(--surface); }
  .dot { width: 4px; height: 4px; border-radius: 50%; background: transparent; }
  .dot.on { background: var(--accent); }
  .selected .dot.on { background: var(--surface); }
  .today {
    align-self: center; border: none; background: transparent; color: var(--accent); font-size: var(--caption); padding: 2px 6px;
    margin-top: calc(var(--spacing) / 2);
  }
</style>
