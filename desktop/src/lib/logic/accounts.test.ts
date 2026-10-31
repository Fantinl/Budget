// Port de AccountTests, AdjustBalanceTests, IzlyAccountTests et de la partie comptes de ReorderTests.
import fileRates from "../../../../rates.json";
import { describe, expect, it } from "vitest";
import { type Account, accountKinds, hasMarketValue, bankLabel, mainAccount, newAccount, newID, MAIN_ACCOUNT_ID, type Transaction } from "../model";
import { day, expense, income, makeStore, op, tick } from "../test/support";
import {
  archiveAccount, balance, banks, deleteAccount, gain, makeIzly, moveAccounts, moveItems, selectableKinds, setDefaultAccount,
  totalBalance, transactionsOf, unarchiveAccount, upsertAccount, value,
} from "./accounts";
import { adjustBalance, balanceGap } from "./adjust";
import { effectiveRate, embeddedRates, hasRegulatedRate, regulatedRate, usesAutoRate } from "./rates";

const account = (fields: Partial<Account> & Pick<Account, "name" | "kind" | "colorIndex">) => newAccount(fields);

describe("Comptes", () => {
  it("le compte par défaut est enregistré et retombe sur le principal une fois archivé", async () => {
    const s = await makeStore();
    const livret = account({ name: "Livret", kind: "livretA", colorIndex: 1 });
    upsertAccount(s, livret);
    setDefaultAccount(s, livret);
    expect(s.defaultAccount.id).toBe(livret.id);
    await s.flush();
    expect((await makeStore(s.directory)).defaultAccountID).toBe(livret.id);
    archiveAccount(s, livret);
    expect(s.defaultAccount.id).toBe(MAIN_ACCOUNT_ID);
    unarchiveAccount(s, livret);
    expect(s.account(livret.id).isArchived).toBe(false);
  });

  it("le compte principal ne peut être ni archivé ni supprimé", async () => {
    const s = await makeStore();
    archiveAccount(s, mainAccount());
    expect(s.account(MAIN_ACCOUNT_ID).isArchived).toBe(false);
    expect(deleteAccount(s, mainAccount())).toBe(false);
    upsertAccount(s, { ...mainAccount(), isArchived: true });
    expect(s.account(MAIN_ACCOUNT_ID).isArchived).toBe(false);
  });

  it("un compte n'est supprimé que s'il est inutilisé", async () => {
    const s = await makeStore();
    const livret = account({ name: "Livret", kind: "livretA", colorIndex: 1 });
    upsertAccount(s, livret);
    s.upsert(income(10, day(2026, 10, 1)));
    s.upsert({ ...income(10, day(2026, 10, 1)), accountID: livret.id });
    expect(deleteAccount(s, livret)).toBe(false);
    s.delete(s.transactions.find(t => t.accountID === livret.id)!);
    expect(deleteAccount(s, livret)).toBe(true);
    expect(s.accounts.some(a => a.id === livret.id)).toBe(false);
  });

  it("calcule les soldes et le patrimoine", async () => {
    const s = await makeStore();
    const livret = account({ name: "Livret", kind: "livretA", colorIndex: 1, initialBalanceCents: 10000 });
    upsertAccount(s, livret);
    s.upsert(income(50, day(2026, 1, 10)));
    s.upsert(expense(20, "otherExpense", day(2026, 1, 20)));
    s.upsert({ ...income(5, day(2026, 1, 20)), accountID: livret.id });
    expect(balance(s, mainAccount())).toBe(3000);
    expect(balance(s, livret)).toBe(10500);
    expect(balance(s, mainAccount(), day(2026, 1, 15))).toBe(5000);
    expect(totalBalance(s)).toBe(13500);
    archiveAccount(s, livret);
    expect(totalBalance(s)).toBe(3000);
    expect(transactionsOf(s, livret)).toHaveLength(1);
  });

  it("valorisation et plus-value des placements", async () => {
    const s = await makeStore();
    const pea = account({ name: "PEA", kind: "pea", colorIndex: 3, initialBalanceCents: 100000, marketValueCents: 120000 });
    expect(value(s, pea)).toBe(120000);
    expect(gain(s, pea)).toBe(20000);
    const av = account({ name: "AV", kind: "assuranceVie", colorIndex: 3, initialBalanceCents: 50000 });
    expect(value(s, av)).toBe(50000);
    expect(gain(s, av)).toBeNull();
    const checking = account({ name: "C", kind: "checking", colorIndex: 0, initialBalanceCents: 1000, marketValueCents: 99900 });
    expect(value(s, checking)).toBe(1000);
    expect(gain(s, checking)).toBeNull();
  });

  it("les banques sont triées et sans doublon", async () => {
    const s = await makeStore();
    upsertAccount(s, account({ name: "A", kind: "livretA", colorIndex: 0, bank: "Boursorama" }));
    upsertAccount(s, account({ name: "B", kind: "ldds", colorIndex: 0, bank: "Boursorama" }));
    upsertAccount(s, account({ name: "C", kind: "pea", colorIndex: 0, bank: "Crédit Agricole" }));
    expect(banks(s)).toEqual(["Boursorama", "Crédit Agricole"]);
    expect(bankLabel(mainAccount())).toBe("Sans banque");
  });

  it("familles, plafonds et valorisation des types", () => {
    expect(accountKinds.livretA.family).toBe("savings");
    expect(accountKinds.pea.family).toBe("investment");
    expect(accountKinds.izly.family).toBe("other");
    expect(accountKinds.livretA.ceilingCents).toBe(2_295_000);
    expect(accountKinds.checking.ceilingCents).toBeNull();
    expect(hasMarketValue("assuranceVie")).toBe(true);
    expect(hasMarketValue("livretA")).toBe(false);
  });

  it("Izly n'est proposé qu'aux étudiants (ou s'il est déjà utilisé)", () => {
    expect(selectableKinds("other", false)).not.toContain("izly");
    expect(selectableKinds("other", true)).toContain("izly");
    expect(selectableKinds("other", false, "izly")).toContain("izly");
  });

  it("réordonne les comptes et enregistre l'ordre", async () => {
    const s = await makeStore();
    upsertAccount(s, account({ id: "a", name: "A", kind: "livretA", colorIndex: 0 }));
    upsertAccount(s, account({ id: "b", name: "B", kind: "ldds", colorIndex: 0 }));
    expect(s.accounts.map(a => a.id)).toEqual(["main", "a", "b"]);
    await tick();
    moveAccounts(s, [2], 1);
    expect(s.accounts.map(a => a.id)).toEqual(["main", "b", "a"]);
    await s.flush();
    expect((await makeStore(s.directory)).accounts.map(a => a.id)).toEqual(["main", "b", "a"]);
  });

  it("moveItems suit la sémantique de SwiftUI", () => {
    const abc = ["A", "B", "C"];
    expect(moveItems(abc, [1], 0)).toEqual(["B", "A", "C"]);
    expect(moveItems(abc, [0], 2)).toEqual(["B", "A", "C"]);
    expect(moveItems(abc, [0], 3)).toEqual(["B", "C", "A"]);
    expect(moveItems(abc, [2], 0)).toEqual(["C", "A", "B"]);
  });
});

describe("Taux réglementés (table embarquée, sans réseau)", () => {
  const rate = async (a: Account) => effectiveRate(await makeStore(), a);

  it("le taux réglementé prime quand il est automatique", async () => {
    const livretA = account({ name: "LA", kind: "livretA", colorIndex: 0, interestRate: 9 });
    expect(usesAutoRate(livretA)).toBe(true);
    expect(await rate(livretA)).toBe(1.7);
    expect(await rate(account({ name: "LEP", kind: "lep", colorIndex: 0 }))).toBe(2.5);
  });

  it("taux saisi quand l'automatique est désactivé", async () => {
    const livret = account({ name: "LA", kind: "livretA", colorIndex: 0, interestRate: 3, autoRate: false });
    expect(usesAutoRate(livret)).toBe(false);
    expect(await rate(livret)).toBe(3);
  });

  it("un compte non réglementé garde son taux", async () => {
    const compte = account({ name: "CSL", kind: "savings", colorIndex: 0, interestRate: 2.1 });
    expect(hasRegulatedRate(compte.kind)).toBe(false);
    expect(regulatedRate(null, compte)).toBeNull();
    expect(await rate(compte)).toBe(2.1);
  });

  it("le taux du PEL dépend de la date d'ouverture", async () => {
    const pel = (openingDate: Date | null) => rate(account({ name: "PEL", kind: "pel", colorIndex: 0, openingDate }));
    expect(await pel(day(2016, 3, 1))).toBe(1.5);
    expect(await pel(day(2020, 6, 1))).toBe(1);
    expect(await pel(day(2024, 6, 1))).toBe(2.25);
    expect(await pel(day(2026, 3, 1))).toBe(2);
    expect(await pel(null)).toBeNull();
    expect(await pel(day(2010, 1, 1))).toBeNull();
  });

  it("le taux du Livret Jeune est un minimum", () => {
    expect(regulatedRate(null, account({ name: "LJ", kind: "livretJeune", colorIndex: 0 }))?.isMinimum).toBe(true);
  });

  it("la date d'effet est lue à minuit à Paris", () => {
    const since = regulatedRate(null, account({ name: "LA", kind: "livretA", colorIndex: 0 }))!.since!;
    expect(since.toISOString()).toBe("2026-07-31T22:00:00.000Z");
  });

  it("la copie embarquée est identique à rates.json", () => {
    const file = fileRates;
    const strip = (rates: Record<string, { rate: number; since: string }>) =>
      Object.fromEntries(Object.entries(rates).map(([k, v]) => [k, [v.rate, v.since]]));
    expect(file.version).toBe(embeddedRates.version);
    expect(file.updatedAt).toBe(embeddedRates.updatedAt);
    expect(strip(file.rates)).toEqual(strip(embeddedRates.rates));
    expect(file.pel.map((e: { from: string; rate: number; verified: boolean }) => [e.from, e.rate, e.verified]))
      .toEqual(embeddedRates.pel.map(e => [e.from, e.rate, e.verified]));
  });
});

describe("Ajustement de solde", () => {
  async function izlyStore() {
    const s = await makeStore();
    const izly = account({ name: "Izly", kind: "izly", colorIndex: 1, initialBalanceCents: 2000 });
    s.accounts = [...s.accounts, izly];
    return { s, izly };
  }
  const opts = { categoryID: "restaurants", note: "Repas" };

  it("un solde plus bas crée une dépense", async () => {
    const { s, izly } = await izlyStore();
    const t = adjustBalance(s, izly, 1300, opts)!;
    expect(t.kind).toBe("expense");
    expect(t.amountCents).toBe(700);
    expect(t.categoryID).toBe("restaurants");
    expect(t.accountID).toBe(izly.id);
    expect(balance(s, izly)).toBe(1300);
    expect(transactionsOf(s, izly)).toHaveLength(1);
  });

  it("un solde plus haut crée un revenu « Autre revenu »", async () => {
    const { s, izly } = await izlyStore();
    adjustBalance(s, izly, 1300, { categoryID: "restaurants", note: "" });
    const r = adjustBalance(s, izly, 1500, { categoryID: "restaurants", note: "Rembours" })!;
    expect(r.kind).toBe("income");
    expect(r.amountCents).toBe(200);
    expect(r.categoryID).toBe("otherIncome");
    expect(balance(s, izly)).toBe(1500);
  });

  it("le même solde ne fait rien", async () => {
    const { s, izly } = await izlyStore();
    expect(adjustBalance(s, izly, 2000, opts)).toBeNull();
    expect(s.transactions).toHaveLength(0);
  });

  it("l'écart est calculé à la date demandée", async () => {
    const { s, izly } = await izlyStore();
    s.upsert({ ...expense(5, "otherExpense", day(2026, 10, 10)), accountID: izly.id });
    expect(balanceGap(s, izly, 1500, day(2026, 10, 12))).toBe(0);
    expect(balanceGap(s, izly, 1500, day(2026, 10, 1))).toBe(-500);
  });

  it("le compte principal est enregistré sans identifiant de compte", async () => {
    const s = await makeStore();
    const t = adjustBalance(s, mainAccount(), 5000, { categoryID: "otherExpense", note: "" })!;
    expect(t.accountID).toBeNull();
    expect(balance(s, mainAccount())).toBe(5000);
  });

  it("s'annule en une étape", async () => {
    const { s, izly } = await izlyStore();
    adjustBalance(s, izly, 1000, { categoryID: "restaurants", note: "x" });
    expect(balance(s, izly)).toBe(1000);
    expect(s.undoActionName).toBe("Ajuster le solde");
    s.undo();
    expect(balance(s, izly)).toBe(2000);
    expect(s.transactions).toHaveLength(0);
  });
});

describe("Compte Izly", () => {
  async function storeWithIzly() {
    const s = await makeStore();
    const izly = account({ name: "Izly", kind: "izly", colorIndex: 2, initialBalanceCents: 500 });
    upsertAccount(s, izly);
    return { s, izly };
  }
  const transfer = (s: Awaited<ReturnType<typeof makeStore>>, from: string, to: string, cents: number) => {
    const id = newID();
    const leg = (kind: "expense" | "income", acc: string): Transaction =>
      op(cents / 100, { kind, categoryID: "transfer", accountID: BudgetAccount(acc), transferID: id, date: new Date() });
    s.transactions = [...s.transactions, leg("expense", from), leg("income", to)];
  };
  const BudgetAccount = (id: string) => (id === MAIN_ACCOUNT_ID ? null : id);

  it("les comptes sélectionnables excluent Izly", async () => {
    const { s, izly } = await storeWithIzly();
    expect(s.selectableAccounts.some(a => a.id === izly.id)).toBe(false);
    expect(s.activeAccounts.some(a => a.id === izly.id)).toBe(true);
    expect(s.selectableAccounts.some(a => a.id === MAIN_ACCOUNT_ID)).toBe(true);
  });

  it("Izly comme compte par défaut retombe sur le principal", async () => {
    const { s, izly } = await storeWithIzly();
    setDefaultAccount(s, izly);
    expect(s.defaultAccount.id).toBe(MAIN_ACCOUNT_ID);
  });

  it("une recharge met à jour les deux soldes", async () => {
    const { s, izly } = await storeWithIzly();
    const before = balance(s, mainAccount());
    transfer(s, MAIN_ACCOUNT_ID, izly.id, 2000);
    expect(balance(s, mainAccount())).toBe(before - 2000);
    expect(balance(s, izly)).toBe(2500);
  });

  it("Izly reste dans le patrimoine", async () => {
    const { s, izly } = await storeWithIzly();
    const before = totalBalance(s);
    transfer(s, MAIN_ACCOUNT_ID, izly.id, 1000);
    expect(totalBalance(s)).toBe(before);
  });

  it("makeIzly prend la première couleur libre et active les repas", () => {
    const izly = makeIzly([account({ name: "A", kind: "cash", colorIndex: 0 }), account({ name: "B", kind: "cash", colorIndex: 1 })], 8);
    expect(izly.colorIndex).toBe(2);
    expect(izly.mealPlan?.isEnabled).toBe(true);
  });
});
