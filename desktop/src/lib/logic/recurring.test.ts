// Port de RecurringTests.swift.
import { describe, expect, it } from "vitest";
import { type Frequency, type Kind, newID, type RecurringOperation } from "../model";
import { day, makeStore } from "../test/support";
import { upsertAccount, setDefaultAccount } from "./accounts";
import { generateDueRecurringOperations, nextOccurrence } from "./recurring";
import { newAccount } from "../model";

const at = (y: number, m: number, d: number) => new Date(y, m - 1, d);

function monthly(start: Date, o: { name?: string; end?: Date | null; frequency?: Frequency; amount?: number; kind?: Kind; account?: string | null } = {}): RecurringOperation {
  return { id: newID(), name: o.name ?? "Loyer", amountCents: Math.round((o.amount ?? 700) * 100), kind: o.kind ?? "expense",
           categoryID: "otherExpense", accountID: o.account ?? null, note: "", frequency: o.frequency ?? "monthly", startDate: start,
           endDate: o.end ?? null, isActive: true, lastGeneratedDate: null };
}

const monthDays = (s: Awaited<ReturnType<typeof makeStore>>, id: string) =>
  s.transactions.filter(t => t.recurringID === id).sort((a, b) => a.date.getTime() - b.date.getTime())
    .map(t => `${t.date.getMonth() + 1}/${t.date.getDate()}`);

describe("Récurrentes", () => {
  it("les fins de mois sont bornées", async () => {
    const s = await makeStore();
    const rec = monthly(at(2026, 1, 31));
    s.recurringOperations = [rec];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    expect(monthDays(s, rec.id)).toEqual(["1/31", "2/28", "3/31", "4/30", "5/31", "6/30", "7/31", "8/31", "9/30"]);
  });

  it("février d'une année bissextile", async () => {
    const s = await makeStore();
    const rec = monthly(at(2028, 1, 31));
    s.recurringOperations = [rec];
    generateDueRecurringOperations(s, at(2028, 3, 1));
    expect(monthDays(s, rec.id)).toEqual(["1/31", "2/29"]);
  });

  it("pas de doublon au second appel", async () => {
    const s = await makeStore();
    s.recurringOperations = [monthly(at(2026, 1, 31))];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    generateDueRecurringOperations(s, at(2026, 10, 17));
    expect(s.transactions).toHaveLength(9);
  });

  it("l'échéance du jour est créée le jour même", async () => {
    const s = await makeStore();
    s.recurringOperations = [monthly(at(2026, 1, 31))];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    generateDueRecurringOperations(s, at(2026, 10, 31));
    expect(s.transactions).toHaveLength(10);
  });

  it("prochaine échéance", async () => {
    const rec = monthly(at(2026, 1, 31));
    expect(nextOccurrence(rec, at(2026, 10, 31))).toEqual(at(2026, 11, 30));
  });

  it("hebdomadaire avec date de fin", async () => {
    const s = await makeStore();
    const weekly = monthly(at(2026, 10, 1), { name: "Marché", end: at(2026, 10, 15), frequency: "weekly", amount: 20 });
    s.recurringOperations = [weekly];
    generateDueRecurringOperations(s, at(2026, 12, 1));
    expect(monthDays(s, weekly.id)).toEqual(["10/1", "10/8", "10/15"]);
  });

  it("trimestriel et annuel", async () => {
    const s = await makeStore();
    const quarterly = monthly(at(2026, 1, 15), { name: "Assurance", frequency: "quarterly" });
    const yearly = monthly(at(2024, 9, 20), { name: "Impôt", frequency: "yearly" });
    s.recurringOperations = [quarterly, yearly];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    expect(monthDays(s, quarterly.id)).toEqual(["1/15", "4/15", "7/15", "10/15"]);
    expect(monthDays(s, yearly.id)).toEqual(["9/20", "9/20", "9/20"]);
  });

  it("une récurrente inactive ne crée rien", async () => {
    const s = await makeStore();
    s.recurringOperations = [{ ...monthly(at(2026, 1, 1)), isActive: false }];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    expect(s.transactions).toHaveLength(0);
  });

  it("un début dans le futur ne crée rien", async () => {
    const s = await makeStore();
    s.recurringOperations = [monthly(at(2026, 12, 1))];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    expect(s.transactions).toHaveLength(0);
  });

  it("les opérations créées sont enregistrées", async () => {
    const s = await makeStore();
    s.recurringOperations = [monthly(at(2026, 8, 1))];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    await s.flush();
    const reloaded = await makeStore(s.directory);
    expect(reloaded.transactions).toHaveLength(3);
    expect(reloaded.recurringOperations[0].lastGeneratedDate).not.toBeNull();
    generateDueRecurringOperations(reloaded, at(2026, 10, 17));
    expect(reloaded.transactions).toHaveLength(3);
  });

  it("sans compte, la récurrente utilise le compte par défaut", async () => {
    const s = await makeStore();
    const livret = newAccount({ name: "Livret", kind: "livretA", colorIndex: 1 });
    upsertAccount(s, livret);
    setDefaultAccount(s, livret);
    const rec = monthly(at(2026, 10, 1));
    s.recurringOperations = [rec];
    generateDueRecurringOperations(s, at(2026, 10, 17));
    expect(s.transactions.find(t => t.recurringID === rec.id)?.accountID).toBe(livret.id);
    expect(day(2026, 1, 1)).toBeInstanceOf(Date);
  });
});
