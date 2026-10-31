<script lang="ts">
  // Pastille ronde : fond à faible opacité, icône en couleur pleine (CategoryBadge de Components.swift).
  // Sert aussi pour les comptes (`icon` + `colorIndex`).
  import Icon from "./Icon.svelte";
  import { categoryColor } from "../lib/theme.svelte";

  let { icon, colorIndex, size }: { icon: string; colorIndex: number; size?: number } = $props();

  const color = $derived(categoryColor(colorIndex));
</script>

<span class="badge" style:--c={color} style:--d={size ? `${size}px` : "var(--icon-size)"}>
  <Icon name={icon} size={Math.round((size ?? 34) * 0.46)} color={color} />
</span>

<style>
  .badge {
    width: var(--d); height: var(--d); border-radius: 50%; flex-shrink: 0;
    display: inline-flex; align-items: center; justify-content: center;
    background: color-mix(in srgb, var(--c) calc(var(--badge-opacity) * 100%), transparent);
  }
</style>
