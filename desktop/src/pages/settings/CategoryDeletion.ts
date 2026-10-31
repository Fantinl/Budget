// Confirmation de suppression d'une catégorie : simple si elle est libre, explicite si elle est utilisée.
import { confirmDialog } from "../../lib/platform";
import type { Category } from "../../lib/model";
import type { BudgetStore } from "../../lib/store.svelte";

/// Demande confirmation puis supprime ; renvoie vrai si la catégorie a été supprimée.
export async function confirmDeleteCategory(s: BudgetStore, category: Category): Promise<boolean> {
  const usage = s.usageCount(category);
  const fallback = s.fallbackCategory(category.kind).label;
  const ok = usage > 0
    ? await confirmDialog(
        `« ${category.label} » est utilisée par ${usage} ${usage === 1 ? "opération" : "opérations"}. Si tu la supprimes, elles seront déplacées dans « ${fallback} ».`,
        { title: "Catégorie utilisée", okLabel: `Supprimer et déplacer dans « ${fallback} »` })
    : await confirmDialog(`Supprimer « ${category.label} » ?`, { title: `Supprimer « ${category.label} » ?`, okLabel: "Supprimer" });
  if (!ok) return false;
  s.deleteCategory(category);
  return true;
}
