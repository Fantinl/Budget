// Confirmation de suppression d'un compte (AccountDeletionDialog de AccountEditor.swift) :
// si le compte a des opérations, on propose de l'archiver à la place.

import type { Account } from "../../lib/model";
import { accountUsageCount, archiveAccount, deleteAccount } from "../../lib/logic/accounts";
import { alertDialog, confirmDialog } from "../../lib/platform";
import type { BudgetStore } from "../../lib/store.svelte";

/// Renvoie vrai si le compte a été supprimé ou archivé.
export async function requestAccountDeletion(s: BudgetStore, account: Account): Promise<boolean> {
  const usage = accountUsageCount(s, account);
  if (usage > 0) {
    const message = `« ${account.name} » contient ${usage} ${usage === 1 ? "opération" : "opérations"} et ne peut pas être supprimé. ` +
      "Tu peux l’archiver : il disparaît des choix, mais ses opérations restent.";
    if (account.isArchived) { await alertDialog(message, "Suppression impossible"); return false; }
    if (!(await confirmDialog(message, { title: "Suppression impossible", okLabel: "Archiver" }))) return false;
    archiveAccount(s, account);
    return true;
  }
  if (!(await confirmDialog(`Supprimer « ${account.name} » ?`, { title: "Supprimer le compte", okLabel: "Supprimer" }))) return false;
  deleteAccount(s, account);
  return true;
}
