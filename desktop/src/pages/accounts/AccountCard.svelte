<script lang="ts" module>
  import { type Account, accountKinds } from "../../lib/model";

  /// Libellé « Banque · Type » d'un compte.
  export function accountSubtitle(account: Account): string {
    const label = accountKinds[account.kind].label;
    return account.bank && account.bank.length > 0 ? `${account.bank} · ${label}` : label;
  }

  const oneDecimal = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 1 });
  const twoDecimals = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 });

  /// Pourcentage lisible en français (« 3,2 % »).
  export const percentText = (value: number) => `${oneDecimal.format(value)} %`;
  export const rateText = (value: number) => twoDecimals.format(value);
</script>

<script lang="ts">
  // Contenu d'une carte de compte façon appli bancaire : en-tête, solde, puis détails selon le type (AccountCardContent).
  // `large` = version de l'en-tête de la page de détail.
  import { store } from "../../lib/app.svelte";
  import { euros } from "../../lib/format";
  import { hasMarketValue } from "../../lib/model";
  import { balance, gain as gainOf, value as valueOf } from "../../lib/logic/accounts";
  import { effectiveRate, regulatedRate, usesAutoRate } from "../../lib/logic/rates";
  import { categoryColor } from "../../lib/theme.svelte";
  import AccountBadge from "../../ui/AccountBadge.svelte";
  import Icon from "../../ui/Icon.svelte";

  let { account, large = false }: { account: Account; large?: boolean } = $props();

  const value = $derived(valueOf(store, account));
  const tint = $derived(categoryColor(account.colorIndex));
  const ceiling = $derived(accountKinds[account.kind].ceilingCents);
  const paid = $derived(balance(store, account));
  const progress = $derived(ceiling && ceiling > 0 ? Math.min(Math.max(paid / ceiling, 0), 1) : 0);
  const gain = $derived(gainOf(store, account));
  const pct = $derived(gain !== null && paid !== 0 ? (gain / paid) * 100 : null);
  const rate = $derived(effectiveRate(store, account));
  const auto = $derived(usesAutoRate(account) && regulatedRate(store, account) !== null);
  const minimum = $derived(auto && account.kind === "livretJeune");
</script>

<div class="card-content">
  <div class="head">
    <AccountBadge {account} size={large ? 48 : 36} />
    <div class="names">
      <div class="name truncate" class:large>{account.name}</div>
      <div class="caption truncate">{accountSubtitle(account)}</div>
    </div>
  </div>

  <div class="large-amount value" class:negative={value < 0}>{euros(value)}</div>

  {#if ceiling !== null}
    <div class="col tight">
      <div class="gauge"><div style:width="{progress * 100}%" style:background={tint}></div></div>
      <div class="caption amount truncate">{euros(paid)} / {euros(ceiling)}</div>
    </div>
  {/if}

  {#if hasMarketValue(account.kind)}
    {#if gain !== null}
      <div class="col tight caption">
        <span class="secondary truncate">Versements : {euros(paid)}</span>
        <span class="row tight nums truncate" class:positive={gain >= 0} class:negative={gain < 0}>
          <Icon name={gain >= 0 ? "arrow.up.right" : "arrow.down.right"} size={11} />
          {(gain > 0 ? "+" : "") + euros(gain) + (pct !== null ? ` (${gain > 0 ? "+" : ""}${percentText(pct)})` : "")}
        </span>
      </div>
    {:else}
      <div class="col tight caption secondary">
        <span>Versements : {euros(paid)}</span>
        <span class="tertiary">Valorisation non renseignée</span>
      </div>
    {/if}
  {/if}

  {#if rate !== null}
    <div class="row tight caption">
      <span class="row tight secondary"><Icon name="percent" size={11} /> Taux {minimum ? "min. " : ""}{rateText(rate)} %</span>
      {#if auto}<span class="tertiary">réglementé</span>{/if}
    </div>
  {/if}
</div>

<style>
  .card-content { display: flex; flex-direction: column; gap: var(--spacing); min-width: 0; text-align: left; }
  .head { display: flex; align-items: center; gap: var(--spacing); min-width: 0; }
  .names { display: flex; flex-direction: column; gap: 2px; min-width: 0; flex: 1; }
  .name { font-size: var(--title); font-weight: var(--title-weight); color: var(--text-primary); }
  .name.large { font-size: var(--large-amount-size); font-weight: var(--large-amount-weight); line-height: 1.15; }
  .value { color: var(--text-primary); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .value.negative { color: var(--negative); }
</style>
