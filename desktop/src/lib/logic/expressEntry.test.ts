import { describe, expect, it } from "vitest";
import { defaultCategories } from "../model";
import { guessCategoryID, parse as parseAt } from "./expressEntry";
import { day, op } from "../test/support";

/// Mercredi 14 octobre 2026, 10 h : date de référence fixe.
const now = day(2026, 10, 14, 10);
const parse = (text: string) => parseAt(text, now);
const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

describe("ExpressEntryParser", () => {
  it("dépense simple", () => {
    const e = parse("café 2,5");
    expect(e.amountCents).toBe(250);
    expect(e.kind).toBe("expense");
    expect(e.label).toBe("Café");
    expect(e.date.getTime()).toBe(now.getTime());
  });

  it("hier et avant-hier", () => {
    const e = parse("essence 60 hier");
    expect(e.amountCents).toBe(6000);
    expect(e.label).toBe("Essence");
    expect(ymd(e.date)).toBe("2026-10-13");
    expect(ymd(parse("pain 1 avant-hier").date)).toBe("2026-10-12");
    expect(ymd(parse("pain 1 avant hier").date)).toBe("2026-10-12");
  });

  it("le signe + indique un revenu", () => {
    const e = parse("+1800 salaire");
    expect(e.amountCents).toBe(180000);
    expect(e.kind).toBe("income");
    expect(e.label).toBe("Salaire");
  });

  it("mots-clés de revenu sans +", () => {
    expect(parse("remboursement 23,40 cpam").kind).toBe("income");
    expect(parse("salaire 1500").kind).toBe("income");
    expect(parse("virement reçu 50").kind).toBe("income");
    expect(parse("courses 50").kind).toBe("expense");
  });

  it("jour du mois", () => {
    const e = parse("loyer 700 le 5");
    expect(e.amountCents).toBe(70000);
    expect(e.label).toBe("Loyer");
    expect(ymd(e.date)).toBe("2026-10-05");
  });

  it("un jour futur du mois renvoie au mois précédent", () => {
    expect(ymd(parse("loyer 700 le 25").date)).toBe("2026-09-25");
    // Le 31 n'existe pas en septembre : on remonte jusqu'à août.
    expect(ymd(parse("truc 5 le 31").date)).toBe("2026-08-31");
  });

  it("aujourd'hui", () => {
    expect(parse("café 2 le 14").date.getTime()).toBe(now.getTime());
    expect(parse("café 2 aujourd'hui").date.getTime()).toBe(now.getTime());
  });

  it("montant calculé", () => {
    const e = parse("12+8,5 déjeuner");
    expect(e.amountCents).toBe(2050);
    expect(e.label).toBe("Déjeuner");
    expect(parse("12 + 8,5 déjeuner").amountCents).toBe(2050);
    expect(parse("3x4,2 cafés").amountCents).toBe(1260);
  });

  it("dates explicites", () => {
    expect(ymd(parse("resto 30 03/10").date)).toBe("2026-10-03");
    expect(ymd(parse("resto 30 03/10/2025").date)).toBe("2025-10-03");
    expect(ymd(parse("resto 30 3/10/25").date)).toBe("2025-10-03");
    expect(ymd(parse("resto 30 le 03/10").date)).toBe("2026-10-03");
  });

  it("date explicite future", () => {
    expect(ymd(parse("resto 30 20/12").date)).toBe("2025-12-20");
    expect(parse("resto 30 20/12/2030").date.getTime()).toBe(now.getTime());
  });

  it("jour de semaine : le plus récent dans le passé", () => {
    expect(ymd(parse("pizza 12 lundi").date)).toBe("2026-10-12");
    expect(ymd(parse("pizza 12 vendredi").date)).toBe("2026-10-09");
    expect(parse("pizza 12 mercredi").date.getTime()).toBe(now.getTime());
  });

  it("montant manquant ou nul", () => {
    const e = parse("café");
    expect(e.amountCents).toBeNull();
    expect(e.label).toBe("Café");
    expect(parse("café 0").amountCents).toBeNull();
  });

  it("devine la catégorie", () => {
    const categories = defaultCategories.map(c => ({ ...c }));
    const quick = [{ id: "q", name: "Café", amountCents: 250, kind: "expense" as const, categoryID: "restaurants", note: "", accountID: null }];
    const guess = (label: string, kind: "expense" | "income" = "expense", history = [] as ReturnType<typeof op>[]) =>
      guessCategoryID(label, kind, categories, quick, history);
    expect(guess("Café")).toBe("restaurants");
    expect(guess("Santé")).toBe("health");
    expect(guess("")).toBe("otherExpense");
    expect(guess("zzz inconnu")).toBe("otherExpense");
    expect(guess("zzz inconnu", "income")).toBe("otherIncome");
    expect(guess("carrefour city")).toBe("groceries");
    const past = op(5, { categoryID: "leisure", note: "Bowling du coin", date: now });
    expect(guess("bowling du coin", "expense", [past])).toBe("leisure");
  });
});
