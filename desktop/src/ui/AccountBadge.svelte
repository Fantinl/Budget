<script lang="ts">
  // Pastille ronde d'un compte : icône du type sur fond couleur (AccountBadge.swift).
  import { type Account, accountKinds } from "../lib/model";
  import CategoryBadge from "./CategoryBadge.svelte";

  let { account, size = 32 }: { account: Account; size?: number } = $props();
</script>

<CategoryBadge icon={accountKinds[account.kind].icon} colorIndex={account.colorIndex} {size} />
