<script lang="ts">
  // Icône d'un nom de symbole SF (voir icons.ts).
  import { iconFor } from "./icons";

  let { name, size = 16, color = "currentColor", strokeWidth = 2 }: {
    name: string; size?: number; color?: string; strokeWidth?: number;
  } = $props();

  const Component = $derived(iconFor(name));
</script>

<Component {size} {color} {strokeWidth} aria-hidden="true" />
