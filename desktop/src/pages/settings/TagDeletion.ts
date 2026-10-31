// Confirmation de suppression d'un tag, explicite s'il est utilisé.
import { confirmDialog } from "../../lib/platform";
import type { Tag } from "../../lib/model";
import type { BudgetStore } from "../../lib/store.svelte";
import { deleteTag, tagUsageCount } from "../../lib/logic/tags";

/// Demande confirmation puis supprime ; renvoie vrai si le tag a été supprimé.
export async function confirmDeleteTag(s: BudgetStore, tag: Tag): Promise<boolean> {
  const usage = tagUsageCount(s, tag);
  const title = `Supprimer « ${tag.name} » ?`;
  const message = usage > 0
    ? `« ${tag.name} » est utilisé par ${usage} ${usage === 1 ? "opération" : "opérations"} : il sera retiré de ${usage === 1 ? "cette opération, qui est conservée" : "ces opérations, qui sont conservées"}.`
    : title;
  if (!(await confirmDialog(message, { title, okLabel: "Supprimer" }))) return false;
  deleteTag(s, tag);
  return true;
}
