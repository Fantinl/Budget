<script lang="ts">
  // Liste des raccourcis clavier et astuces de saisie (« Raccourcis clavier », ShortcutsView.swift).
  // À ouvrir avec : {#if open}<ShortcutsSheet onclose={() => (open = false)} />{/if}   (Ctrl/⌘ + /)
  import Sheet from "../../ui/Sheet.svelte";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import { Sigma } from "@lucide/svelte";
  import { isMac } from "./keys";

  let { onclose }: { onclose: () => void } = $props();

  /// Touches : « mod » = ⌘ / Ctrl, « shift » = ⇧ / Maj, « alt » = ⌥ / Alt.
  const names: Record<string, string> = isMac
    ? { mod: "⌘", shift: "⇧", alt: "⌥", back: "⌫", enter: "↩", click: "clic" }
    : { mod: "Ctrl", shift: "Maj", alt: "Alt", back: "Suppr", enter: "Entrée", click: "clic" };
  const label = (key: string) => names[key] ?? key;

  interface Item { action: string; keys: string[] }
  interface Group { title: string; icon: string; items: Item[] }

  const groups: Group[] = [
    { title: "Général", icon: "gearshape", items: [
      { action: "Réglages", keys: ["mod", ","] },
      { action: "Raccourcis clavier", keys: ["mod", "/"] },
      { action: "Annuler", keys: ["mod", "Z"] },
      { action: "Rétablir", keys: ["shift", "mod", "Z"] },
    ] },
    { title: "Opérations", icon: "list.bullet", items: [
      { action: "Nouvelle opération", keys: ["mod", "N"] },
      { action: "Saisie express", keys: ["mod", "E"] },
      { action: "Rechercher", keys: ["mod", "F"] },
      { action: "Ajout rapide (dans l'ordre affiché)", keys: ["mod", "1 … 9"] },
    ] },
    { title: "Navigation", icon: "calendar", items: [
      { action: "Mois précédent", keys: ["mod", "←"] },
      { action: "Mois suivant", keys: ["mod", "→"] },
    ] },
    { title: "Sélection", icon: "checkmark.circle", items: [
      { action: "Ajouter / retirer une ligne", keys: ["mod", "click"] },
      { action: "Sélectionner une plage", keys: ["shift", "click"] },
      { action: "Tout sélectionner", keys: ["mod", "A"] },
      { action: "Supprimer la sélection", keys: [isMac ? "back" : "Suppr"] },
      { action: "Annuler la sélection / vider la recherche", keys: ["Échap"] },
    ] },
    { title: "Saisie", icon: "sparkles", items: [
      { action: "Enregistrer la saisie express", keys: ["enter"] },
      { action: "Ouvrir le formulaire complet", keys: ["alt", "enter"] },
    ] },
  ];

  const tips = [
    { icon: "function", title: "Calcul dans les montants", text: "Tape « 12,5+8 » dans un champ montant : 20,50 €." },
    { icon: "sparkles", title: "Exemples de saisie express", text: "« café 2,5 », « courses 45 hier », « +1800 salaire »." },
    { icon: "square.and.arrow.down", title: "Importer un relevé", text: "Glisse le fichier CSV de ta banque sur la fenêtre." },
  ];
</script>

<Sheet title="Raccourcis clavier" {onclose} width={520}>
  {#each groups as group (group.title)}
    <section>
      <h3 class="title"><Icon name={group.icon} size={15} />{group.title}</h3>
      <Card padded={false}>
        {#each group.items as item, index (item.action)}
          {#if index > 0}<hr class="separator" />{/if}
          <div class="item">
            <span>{item.action}</span>
            <span class="keys">{#each item.keys as key, i (i)}<kbd>{label(key)}</kbd>{/each}</span>
          </div>
        {/each}
      </Card>
    </section>
  {/each}

  <section>
    <h3 class="title"><Icon name="lightbulb" size={15} />Astuces</h3>
    <Card>
      {#each tips as tip (tip.title)}
        <div class="tip">
          <span class="tip-icon">{#if tip.icon === "function"}<Sigma size={16} color="var(--accent)" aria-hidden="true" />{:else}<Icon name={tip.icon} size={16} color="var(--accent)" />{/if}</span>
          <div class="col tight"><span>{tip.title}</span><span class="caption">{tip.text}</span></div>
        </div>
      {/each}
    </Card>
  </section>

  {#snippet footer()}
    <button type="button" class="btn" onclick={onclose}>Fermer</button>
  {/snippet}
</Sheet>

<style>
  section { display: flex; flex-direction: column; gap: 6px; }
  h3 { margin: 0; display: flex; align-items: center; gap: 6px; padding-left: 6px; }
  .item { display: flex; align-items: center; justify-content: space-between; gap: var(--spacing); padding: var(--spacing) var(--padding); }
  .keys { display: inline-flex; gap: 4px; flex-shrink: 0; }
  kbd {
    font: inherit; font-family: ui-monospace, "Cascadia Mono", Menlo, monospace; font-size: var(--caption);
    min-width: 26px; height: 24px; padding: 0 var(--spacing); display: inline-flex; align-items: center; justify-content: center;
    background: var(--surface-secondary); border: 1px solid var(--separator); border-radius: calc(var(--radius) / 2);
  }
  .tip { display: flex; gap: var(--spacing); align-items: flex-start; }
  .tip-icon { width: var(--icon-size); display: inline-flex; justify-content: center; padding-top: 2px; flex-shrink: 0; }
</style>
