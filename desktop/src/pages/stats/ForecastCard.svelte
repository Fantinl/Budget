<script lang="ts">
  // Carte « Prévision » détaillée (Statistiques, mois en cours) (ForecastCard.swift).
  import { store } from "../../lib/app.svelte";
  import { euros, shortDate } from "../../lib/format";
  import { monthForecast } from "../../lib/logic/forecast";
  import Card from "../../ui/Card.svelte";

  const forecast = $derived(monthForecast(store));
</script>

{#snippet line(title: string, cents: number)}
  <div class="line">
    <span>{title}</span>
    <span class="amount">{euros(cents)}</span>
  </div>
{/snippet}

<Card>
  <span class="title">Prévision</span>
  {@render line("Solde actuel du mois", forecast.currentCents)}
  {#if forecast.upcoming.length === 0}
    <span class="caption">Aucune opération récurrente à venir ce mois-ci.</span>
  {:else}
    {@render line("+ Récurrentes à venir", forecast.upcomingTotalCents)}
    {#each forecast.upcoming as item (item.id)}
      <div class="line caption upcoming">
        <span class="truncate">{shortDate(item.date)} · {item.name}</span>
        <span class="nums">{euros(item.amountCents)}</span>
      </div>
    {/each}
  {/if}
  {#if forecast.estimatedSpendingCents !== null}
    {@render line("+ Dépenses courantes estimées", -forecast.estimatedSpendingCents)}
  {:else}
    <span class="caption tertiary">Pas assez d'historique pour estimer les dépenses courantes.</span>
  {/if}
  <hr class="separator" />
  <div class="line">
    <span>= Fin de mois prévue</span>
    <span class="amount" style:color={forecast.projectedCents >= 0 ? "var(--positive)" : "var(--negative)"}>{euros(forecast.projectedCents)}</span>
  </div>
  <span class="caption tertiary">Prévu = revenus − dépenses du mois à ce jour, plus les opérations récurrentes à venir, moins une estimation des dépenses courantes (moyenne journalière hors récurrentes des 3 mois précédents × jours restants). Les virements sont ignorés.</span>
</Card>

<style>
  .upcoming { padding-left: var(--spacing); }
</style>
