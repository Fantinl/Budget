import { describe, expect, it } from "vitest";
import { containsOperator, evaluate, positiveAmount } from "./amountExpression";

describe("AmountExpression", () => {
  it("lit les nombres simples", () => {
    expect(evaluate("12")).toBe(1200);
    expect(evaluate("12,5")).toBe(1250);
    expect(evaluate("12.5")).toBe(1250);
    expect(evaluate("1 234,56 €")).toBe(123456);
  });

  it("respecte opérateurs et priorités", () => {
    expect(evaluate("12+8,5")).toBe(2050);
    expect(evaluate("10-3-2")).toBe(500);
    expect(evaluate("2+3*4")).toBe(1400);
    expect(evaluate("(2+3)*4")).toBe(2000);
    expect(evaluate("20/4")).toBe(500);
    expect(evaluate("(3×4,20)+2")).toBe(1460);
    expect(evaluate("3x2")).toBe(600);
    expect(evaluate("9÷3")).toBe(300);
    expect(evaluate("10−4")).toBe(600);
  });

  it("gère les signes et l'arrondi", () => {
    expect(evaluate("-5")).toBe(-500);
    expect(evaluate("+5")).toBe(500);
    expect(evaluate("10/3")).toBe(333);
    expect(evaluate("0,005")).toBe(1);
    expect(evaluate("-0,005")).toBe(-1);
  });

  it("refuse les expressions invalides", () => {
    for (const text of ["", "abc", "1+", "(1+2", "1/0", "1..2+"]) expect(evaluate(text)).toBeNull();
  });

  it("traite les espaces dans un nombre comme des séparateurs de milliers", () => {
    expect(evaluate("1 234")).toBe(123400);
  });

  it("positiveAmount", () => {
    expect(positiveAmount("3+4")).toBe(700);
    expect(positiveAmount("0")).toBeNull();
    expect(positiveAmount("-3")).toBeNull();
    expect(positiveAmount("x")).toBeNull();
  });

  it("containsOperator", () => {
    expect(containsOperator("12,5")).toBe(false);
    expect(containsOperator("-12")).toBe(false);
    expect(containsOperator("12+3")).toBe(true);
    expect(containsOperator("(12)")).toBe(true);
  });
});
