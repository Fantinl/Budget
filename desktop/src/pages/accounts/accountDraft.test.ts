import { describe, expect, it } from "vitest";
import { newAccount } from "../../lib/model";
import { draftFrom, newDraft, parseDecimal, refreshName, validated } from "./accountDraft";

describe("Brouillon de compte", () => {
  it("propose un nom d'après le type et la banque", () => {
    const d = newDraft(3);
    expect(d.account.name).toBe("Compte courant");
    d.bankText = "Boursorama";
    refreshName(d);
    expect(d.account.name).toBe("Compte courant Boursorama");
    d.account.kind = "cash";
    refreshName(d);
    expect(d.account.name).toBe("Espèces");
    d.account.name = "Mon nom";
    d.nameIsAuto = false;
    d.account.kind = "pea";
    refreshName(d);
    expect(d.account.name).toBe("Mon nom");
  });

  it("lit les montants saisis", () => {
    expect(parseDecimal("1 234,50")).toBe(1234.5);
    expect(parseDecimal("-20.5")).toBe(-20.5);
    expect(parseDecimal("abc")).toBeNull();
    expect(parseDecimal("")).toBeNull();
  });

  it("valide : solde vide = 0, montant illisible refusé", () => {
    const d = newDraft(0);
    expect(validated(d)?.initialBalanceCents).toBe(0);
    d.balanceText = "12,5";
    expect(validated(d)?.initialBalanceCents).toBe(1250);
    d.balanceText = "x";
    expect(validated(d)).toBeNull();
  });

  it("nettoie les champs inutiles selon le type", () => {
    const a = newAccount({ name: "PEL", kind: "livretA", colorIndex: 0, bank: "X", openingDate: new Date(), marketValueCents: 5, interestRate: 3 });
    const d = draftFrom(a);
    d.account.kind = "cash";
    d.rateText = "4";
    const v = validated(d)!;
    expect(v.bank).toBeNull();
    expect(v.openingDate).toBeNull();
    expect(v.autoRate).toBeNull();
    expect(v.marketValueCents).toBeNull();
    expect(v.interestRate).toBeNull();
  });

  it("taux saisi pour un livret non réglementé, valorisation pour un placement", () => {
    const d = newDraft(0);
    d.account.kind = "savings";
    d.rateText = "2,1";
    expect(validated(d)?.interestRate).toBe(2.1);
    d.account.kind = "pea";
    d.marketValueText = "1200";
    const v = validated(d)!;
    expect(v.marketValueCents).toBe(120000);
    expect(v.interestRate).toBeNull();
  });

  it("taux automatique : le taux saisi est ignoré", () => {
    const d = newDraft(0);
    d.account.kind = "livretA";
    d.rateText = "9";
    expect(validated(d)?.interestRate).toBeNull();
    d.account.autoRate = false;
    expect(validated(d)?.interestRate).toBe(9);
  });
});
