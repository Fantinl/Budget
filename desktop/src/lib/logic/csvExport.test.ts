import { describe, expect, it } from "vitest";
import { makeStore, day, expense, income } from "../test/support";
import { MAIN_ACCOUNT_ID, newAccount } from "../model";
import { csvEscape, csvFileName, csvInterval, csvText } from "./csvExport";
import { createTransfer } from "./transfers";

const lines = (text: string) => text.split("\r\n").filter(l => l.length > 0);
const startOfDay = (y: number, m: number, d: number) => new Date(y, m - 1, d);

describe("Export CSV", () => {
  it("en-tête et BOM", async () => {
    const s = await makeStore();
    const text = csvText(s, []);
    expect(text.charCodeAt(0)).toBe(0xFEFF);
    expect(lines(text)[0].endsWith("Date;Type;Catégorie;Compte;Description;Montant")).toBe(true);
  });

  it("montants français signés", async () => {
    const s = await makeStore();
    s.upsert({ ...expense(700, "housing", day(2026, 10, 5)), note: "Loyer" });
    s.upsert({ ...income(1234.5, day(2026, 10, 28), "salary"), note: "Salaire" });
    const l = lines(csvText(s, s.transactions));
    expect(l[1]).toBe("05/10/2026;Dépense;Logement;Compte courant;Loyer;-700,00");
    expect(l[2]).toBe("28/10/2026;Revenu;Salaire;Compte courant;Salaire;1234,50");
  });

  it("échappe les caractères spéciaux", () => {
    expect(csvEscape("simple")).toBe("simple");
    expect(csvEscape("a;b")).toBe('"a;b"');
    expect(csvEscape('dit "oui"')).toBe('"dit ""oui"""');
    expect(csvEscape("l1\nl2")).toBe('"l1\nl2"');
  });

  it("montre un virement comme tel", async () => {
    const s = await makeStore();
    const livret = newAccount({ name: "Livret", kind: "livretA", colorIndex: 1 });
    s.accounts = [...s.accounts, livret];
    createTransfer(s, MAIN_ACCOUNT_ID, livret.id, 5000, day(2026, 10, 1), "");
    const l = lines(csvText(s, s.transactions));
    expect(l).toHaveLength(3);
    expect(l.slice(1).every(x => x.includes(";Virement;Virement;"))).toBe(true);
  });

  it("trie par date", async () => {
    const s = await makeStore();
    s.upsert({ ...expense(1, "otherExpense", day(2026, 10, 9)), note: "B" });
    s.upsert({ ...expense(1, "otherExpense", day(2026, 10, 2)), note: "A" });
    const l = lines(csvText(s, s.transactions));
    expect(l[1].startsWith("02/10/2026")).toBe(true);
    expect(l[2].startsWith("09/10/2026")).toBe(true);
  });

  it("périodes et noms de fichier", () => {
    const now = day(2026, 10, 17);
    const from = day(2026, 3, 10), to = day(2026, 1, 5); // inversés exprès
    expect(csvInterval("thisMonth", from, to, now)?.start).toEqual(startOfDay(2026, 10, 1));
    expect(csvInterval("lastMonth", from, to, now)?.start).toEqual(startOfDay(2026, 9, 1));
    expect(csvInterval("thisYear", from, to, now)?.end).toEqual(startOfDay(2027, 1, 1));
    expect(csvInterval("all", from, to, now)).toBeNull();
    const custom = csvInterval("custom", from, to, now);
    expect(custom?.start).toEqual(startOfDay(2026, 1, 5));
    expect(custom?.end).toEqual(startOfDay(2026, 3, 11));
    expect(csvFileName("thisMonth", from, to, now)).toBe("Budget-2026-10.csv");
    expect(csvFileName("lastMonth", from, to, now)).toBe("Budget-2026-09.csv");
    expect(csvFileName("thisYear", from, to, now)).toBe("Budget-2026.csv");
    expect(csvFileName("all", from, to, now)).toBe("Budget-tout.csv");
    expect(csvFileName("custom", from, to, now)).toBe("Budget-2026-01-05_2026-03-10.csv");
  });
});
