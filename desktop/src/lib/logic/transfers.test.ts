import { describe, expect, it } from "vitest";
import { isEarning, isSpending, MAIN_ACCOUNT_ID, newAccount } from "../model";
import { makeStore, day, tick } from "../test/support";
import { balance } from "./accounts";
import { counterpartAccount, createTransfer, DEFAULT_TRANSFER_NOTE, deleteTransfer, transferLegs, updateTransfer } from "./transfers";
import { deleteTransactions, duplicateTransactions, updateTransactions } from "./bulk";

const livret = newAccount({ name: "Livret", kind: "livretA", colorIndex: 1 });

async function storeWithLivret() {
  const s = await makeStore();
  s.accounts = [...s.accounts, livret];
  return s;
}

describe("Virements", () => {
  it("déplace l'argent entre comptes", async () => {
    const s = await storeWithLivret();
    const id = createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 10000, day(2026, 10, 1), "")!;
    const legs = transferLegs(s, id)!;
    expect(legs.out.kind).toBe("expense");
    expect(legs.in.kind).toBe("income");
    expect(legs.out.note).toBe(DEFAULT_TRANSFER_NOTE);
    expect(balance(s, s.account(MAIN_ACCOUNT_ID))).toBe(-10000);
    expect(balance(s, livret)).toBe(10000);
    expect(counterpartAccount(s, legs.out)?.id).toBe(livret.id);
    expect(counterpartAccount(s, legs.in)?.id).toBe(MAIN_ACCOUNT_ID);
  });

  it("n'est ni une dépense ni un revenu", async () => {
    const s = await storeWithLivret();
    createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 10000, day(2026, 10, 1), "");
    const month = s.transactionsInMonthOf(day(2026, 10, 1));
    expect(month).toHaveLength(2);
    expect(month.filter(isSpending)).toHaveLength(0);
    expect(month.filter(isEarning)).toHaveLength(0);
  });

  it("refuse les virements invalides", async () => {
    const s = await storeWithLivret();
    expect(createTransfer(s, livret.id, livret.id, 500, day(2026, 10, 1), "")).toBeNull();
    expect(createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 0, day(2026, 10, 1), "")).toBeNull();
    expect(createTransfer(s, MAIN_ACCOUNT_ID, livret.id, -300, day(2026, 10, 1), "")).toBeNull();
    expect(s.transactions).toHaveLength(0);
  });

  it("supprimer une jambe supprime tout le virement", async () => {
    const s = await storeWithLivret();
    const id = createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 10000, day(2026, 10, 1), "")!;
    const leg = s.transactions.find(t => t.transferID === id)!;
    expect(deleteTransactions(s, new Set([leg.id]))).toBe(2);
    expect(s.transactions).toHaveLength(0);
  });

  it("supprime un virement", async () => {
    const s = await storeWithLivret();
    const id = createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 10000, day(2026, 10, 1), "")!;
    await tick();
    deleteTransfer(s, id);
    expect(s.transactions).toHaveLength(0);
    s.undo();
    expect(s.transactions).toHaveLength(2);
    expect(s.undoActionName).toBe("Créer un virement");
  });

  it("modifie un virement", async () => {
    const s = await storeWithLivret();
    const id = createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 10000, day(2026, 10, 1), "")!;
    updateTransfer(s, id, livret.id, MAIN_ACCOUNT_ID, 4000, day(2026, 10, 3), " Retour ");
    const legs = transferLegs(s, id)!;
    expect(legs.out.accountID).toBe(livret.id);
    expect(legs.in.accountID).toBeNull();
    expect(legs.out.amountCents).toBe(4000);
    expect(legs.in.note).toBe("Retour");
    expect(balance(s, s.account(MAIN_ACCOUNT_ID))).toBe(4000);
  });

  it("les actions groupées ignorent les virements", async () => {
    const s = await storeWithLivret();
    const id = createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 10000, day(2026, 10, 1), "")!;
    const ids = new Set(s.transactions.filter(t => t.transferID === id).map(t => t.id));
    expect(updateTransactions(s, ids, t => ({ ...t, categoryID: "leisure" }))).toBe(0);
    expect(duplicateTransactions(s, ids)).toEqual([]);
  });
});
