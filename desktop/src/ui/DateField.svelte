<script lang="ts">
  // Champ de date minimaliste : date en clair, raccourcis en pastilles, calendrier repliable. Port de DateField.swift.
  import { addDays, addMonths, daysInMonth, isSameDay, startOfDay, startOfMonth } from "../lib/dates";
  import Icon from "./Icon.svelte";

  let { value, onchange, label }: { value: Date; onchange: (d: Date) => void; label?: string } = $props();

  let showsCalendar = $state(false);
  /// Mois affiché dans le calendrier.
  let shown = $state(startOfMonth(new Date()));

  const today = $derived(startOfDay(new Date()));
  const chips = ["Aujourd'hui", "Hier", "Avant-hier"];

  const capitalizeFirst = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
  const withYear = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  const withoutYear = new Intl.DateTimeFormat("fr-FR", { weekday: "long", day: "numeric", month: "long" });
  const monthFormat = new Intl.DateTimeFormat("fr-FR", { month: "long", year: "numeric" });

  /// « Aujourd'hui », « Hier » ou « jeudi 15 octobre » (année ajoutée si différente).
  const title = $derived.by(() => {
    const now = new Date();
    if (isSameDay(value, now)) return "Aujourd'hui";
    if (isSameDay(value, addDays(now, -1))) return "Hier";
    return capitalizeFirst((value.getFullYear() === now.getFullYear() ? withoutYear : withYear).format(value));
  });

  function pickChip(offset: number) {
    onchange(addDays(today, -offset));
    showsCalendar = false;
  }

  function toggleCalendar() {
    showsCalendar = !showsCalendar;
    if (showsCalendar) shown = startOfMonth(value);
  }

  /// Cases du calendrier (semaine commençant le lundi) ; null = case vide.
  const cells = $derived.by(() => {
    const lead = (shown.getDay() + 6) % 7;
    const days = daysInMonth(shown);
    return Array.from({ length: Math.ceil((lead + days) / 7) * 7 }, (_, i) => {
      const n = i - lead + 1;
      return n >= 1 && n <= days ? new Date(shown.getFullYear(), shown.getMonth(), n) : null;
    });
  });

  /// Choisir un jour dans le calendrier le replie (l'heure de la date est conservée).
  function pickDay(d: Date) {
    onchange(new Date(d.getFullYear(), d.getMonth(), d.getDate(), value.getHours(), value.getMinutes(), value.getSeconds(), value.getMilliseconds()));
    showsCalendar = false;
  }

  const canGoForward = $derived(addMonths(shown, 1).getTime() <= today.getTime());
</script>

<div class="date-field" aria-label={label}>
  <span class="heading">{title}</span>

  <div class="chips">
    {#each chips as text, offset (offset)}
      <button type="button" class="chip" class:selected={isSameDay(value, addDays(today, -offset))} onclick={() => pickChip(offset)}>{text}</button>
    {/each}
  </div>

  <hr class="separator" />

  <button type="button" class="toggle" onclick={toggleCalendar}>
    <Icon name="calendar" size={14} />
    <span>Choisir une date</span>
    <span class="spacer"></span>
    <span class="chevron" class:open={showsCalendar}><Icon name="chevron.down" size={14} /></span>
  </button>

  {#if showsCalendar}
    <div class="calendar">
      <div class="nav">
        <button type="button" class="btn icon plain" aria-label="Mois précédent" onclick={() => (shown = addMonths(shown, -1))}><Icon name="chevron.left" size={14} /></button>
        <span class="month">{capitalizeFirst(monthFormat.format(shown))}</span>
        <button type="button" class="btn icon plain" aria-label="Mois suivant" disabled={!canGoForward} onclick={() => (shown = addMonths(shown, 1))}><Icon name="chevron.right" size={14} /></button>
      </div>
      <div class="grid7 caption">
        {#each ["L", "M", "M", "J", "V", "S", "D"] as d, i (i)}<span class="dow">{d}</span>{/each}
        {#each cells as cell, i (i)}
          {#if cell}
            <button type="button" class="day" class:selected={isSameDay(cell, value)} class:today={isSameDay(cell, today)}
                    disabled={cell.getTime() > new Date().getTime()} onclick={() => pickDay(cell)}>{cell.getDate()}</button>
          {:else}
            <span></span>
          {/if}
        {/each}
      </div>
    </div>
  {/if}
</div>

<style>
  .date-field { display: flex; flex-direction: column; gap: var(--spacing); }
  .heading { font-size: var(--title); font-weight: var(--title-weight); color: var(--text-primary); }
  .chips { display: flex; gap: 6px; }
  .chip {
    flex: 1; min-width: 0; border: none; padding: 7px var(--spacing); border-radius: 999px; white-space: nowrap;
    overflow: hidden; text-overflow: ellipsis; font-size: var(--caption);
    background: var(--surface-secondary); color: var(--text-secondary);
  }
  .chip.selected { background: var(--accent); color: var(--surface); }
  .toggle {
    display: flex; align-items: center; gap: 6px; border: none; background: transparent; padding: 0;
    color: var(--text-secondary); text-align: left;
  }
  .chevron { display: inline-flex; transition: transform 0.25s; }
  .chevron.open { transform: rotate(180deg); }
  .calendar { max-width: 340px; width: 100%; align-self: center; display: flex; flex-direction: column; gap: 6px; }
  .nav { display: flex; align-items: center; justify-content: space-between; }
  .month { font-weight: 600; }
  .grid7 { display: grid; grid-template-columns: repeat(7, 1fr); gap: 2px; text-align: center; }
  .dow { padding: 4px 0; color: var(--text-tertiary); }
  .day {
    height: 30px; border: none; border-radius: 50%; background: transparent; color: var(--text-primary); font-size: var(--body);
  }
  .day:hover:not(:disabled) { background: var(--surface-secondary); }
  .day.today { color: var(--accent); font-weight: 600; }
  .day.selected { background: var(--accent); color: var(--on-accent); }
  .day:disabled { color: var(--text-tertiary); opacity: 0.5; }
</style>
