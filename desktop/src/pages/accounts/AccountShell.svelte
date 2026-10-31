<script lang="ts">
  // Fond d'une carte de compte (AccountCardBackground) : surface, dégradé léger de la couleur du compte, bandeau en haut.
  import type { Snippet } from "svelte";
  import type { Account } from "../../lib/model";
  import { categoryColor } from "../../lib/theme.svelte";

  let { account, archived = false, children, class: className = "" }: {
    account: Account; archived?: boolean; children: Snippet; class?: string;
  } = $props();
</script>

<div class="shell {className}" class:archived style:--tint={categoryColor(account.colorIndex)}>
  {@render children()}
</div>

<style>
  .shell {
    position: relative; overflow: hidden; width: 100%; min-width: 0; padding: var(--padding);
    border-radius: var(--radius); border: var(--card-border-width) solid var(--card-border); box-shadow: var(--card-shadow);
    background:
      linear-gradient(135deg, color-mix(in srgb, var(--tint) 22%, transparent), color-mix(in srgb, var(--tint) 4%, transparent)),
      var(--surface);
  }
  .shell::before { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 4px; background: var(--tint); }
  .archived { opacity: 0.55; }
</style>
