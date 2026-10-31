// Vérifie que la page Opérations et ses feuilles s'affichent (rendu serveur) avec des données.
import { describe, expect, it } from "vitest";
import { render } from "svelte/server";
import { makeStore, expense, income, day } from "../../lib/test/support";
import { setStore } from "../../lib/app.svelte";
import { MAIN_ACCOUNT_ID, newAccount } from "../../lib/model";
import { createTransfer } from "../../lib/logic/transfers";
import { addTag } from "../../lib/logic/tags";
import OperationsPage from "./OperationsPage.svelte";
import TransactionForm from "./TransactionForm.svelte";
import TransferEditor from "./TransferEditor.svelte";
import BulkEditSheet from "./BulkEditSheet.svelte";
import ShortcutsSheet from "./ShortcutsSheet.svelte";

describe("page Opérations", () => {
  it("s'affiche avec des opérations, un virement et des tags", async () => {
    const s = await makeStore();
    const livret = newAccount({ name: "Livret", kind: "livretA", colorIndex: 1 });
    s.accounts = [...s.accounts, livret];
    const tag = addTag(s, "Vacances");
    const now = new Date();
    const d = new Date(now.getFullYear(), now.getMonth(), 1, 12);
    s.upsert({ ...expense(12.5, "restaurants", d), note: "Déjeuner", tagIDs: [tag.id] });
    s.upsert(income(1500, d));
    createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 5000, d, "");
    setStore(s);

    const page = render(OperationsPage).body;
    expect(page).toContain("Déjeuner");
    expect(page).toContain("Virement vers Livret");
    expect(page).toContain("Solde du mois");
    expect(page).toContain("Ajouter");
    expect(page).toContain("Vacances");

    const detail = render(OperationsPage, { props: { accountID: livret.id } }).body;
    expect(detail).toContain("Solde actuel");
    expect(detail).toContain("Livret A");
  });

  it("affiche l'état vide", async () => {
    setStore(await makeStore());
    expect(render(OperationsPage).body).toContain("Aucune opération ce mois-ci");
  });

  it("rend les feuilles", async () => {
    const s = await makeStore();
    const t = { ...expense(8, "groceries", day(2026, 10, 3)), note: "Pain" };
    s.upsert(t);
    setStore(s);
    expect(render(TransactionForm, { props: { draft: { transaction: t, isNew: false }, onclose() {} } }).body).toContain("Supprimer");
    expect(render(TransactionForm, { props: { draft: { transaction: t, isNew: true }, onclose() {} } }).body).toContain("Nouvelle opération");
    expect(render(TransferEditor, { props: { transferID: null, onclose() {} } }).body).toContain("Nouveau virement");
    expect(render(BulkEditSheet, { props: { transactions: [t], onclose() {} } }).body).toContain("Modifier 1 opération");
    expect(render(ShortcutsSheet, { props: { onclose() {} } }).body).toContain("Saisie express");
  });
});
