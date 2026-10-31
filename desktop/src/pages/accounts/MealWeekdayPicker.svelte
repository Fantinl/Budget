<script lang="ts">
  // Sept pastilles L M M J V S D pour choisir les jours de la semaine (numérotation 1 = dimanche).
  let { weekdays, onchange }: { weekdays: number[]; onchange: (weekdays: number[]) => void } = $props();

  const days = [
    { weekday: 2, letter: "L", name: "lundi" }, { weekday: 3, letter: "M", name: "mardi" },
    { weekday: 4, letter: "M", name: "mercredi" }, { weekday: 5, letter: "J", name: "jeudi" },
    { weekday: 6, letter: "V", name: "vendredi" }, { weekday: 7, letter: "S", name: "samedi" },
    { weekday: 1, letter: "D", name: "dimanche" },
  ];

  function toggle(weekday: number) {
    onchange(weekdays.includes(weekday) ? weekdays.filter(d => d !== weekday) : [...weekdays, weekday].sort((a, b) => a - b));
  }
</script>

<div class="days">
  {#each days as day (day.weekday)}
    {@const selected = weekdays.includes(day.weekday)}
    <button type="button" class="day" class:selected aria-label={day.name} aria-pressed={selected} title={day.name} onclick={() => toggle(day.weekday)}>
      {day.letter}
    </button>
  {/each}
</div>

<style>
  .days { display: flex; gap: calc(var(--spacing) / 2); }
  .day {
    width: 32px; height: 32px; border-radius: 50%; border: none; font-size: var(--caption);
    background: var(--surface-secondary); color: var(--text-secondary);
  }
  .day.selected { background: var(--accent); color: var(--on-accent); }
</style>
