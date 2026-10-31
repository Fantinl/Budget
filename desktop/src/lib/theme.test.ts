// Port de ThemeTests.swift (contrastes calculés sur les couleurs CSS du thème).
import { describe, expect, it } from "vitest";
import { type Adaptive, themeNamed, themes } from "./theme.svelte";

function rgb(color: string): [number, number, number] {
  const hex = /^#([0-9a-f]{6})$/i.exec(color);
  if (hex) { const n = parseInt(hex[1], 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
  const m = /^rgba?\(([^)]+)\)$/.exec(color);
  if (m) return m[1].split(",").slice(0, 3).map(Number) as [number, number, number];
  throw new Error(`couleur illisible : ${color}`);
}
const pick = (c: Adaptive, dark: boolean) => (typeof c === "string" ? c : dark ? c.dark : c.light);
const luminance = ([r, g, b]: [number, number, number]) => {
  const lin = (v: number) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
};
function contrast(a: Adaptive, b: Adaptive, dark: boolean) {
  const la = luminance(rgb(pick(a, dark))), lb = luminance(rgb(pick(b, dark)));
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

describe("Thèmes", () => {
  it("tous les thèmes sont enregistrés", () => {
    expect(themes).toHaveLength(6);
    expect(new Set(themes.map(t => t.id)).size).toBe(6);
    for (const t of themes) {
      expect(themeNamed(t.id).id).toBe(t.id);
      expect(t.categoryPalette).toHaveLength(12);
    }
  });

  it("un identifiant inconnu retombe sur le thème par défaut", () => {
    expect(themeNamed("inconnu").id).toBe("minimal");
  });

  it("le texte reste lisible", () => {
    for (const t of themes) {
      for (const dark of [false, true]) {
        const name = `${t.name} ${dark ? "sombre" : "clair"}`;
        expect(contrast(t.textPrimary, t.background, dark), `${name} texte/fond`).toBeGreaterThanOrEqual(4.5);
        expect(contrast(t.textPrimary, t.surface, dark), `${name} texte/carte`).toBeGreaterThanOrEqual(4.5);
        expect(contrast(t.textSecondary, t.surface, dark), `${name} secondaire/carte`).toBeGreaterThanOrEqual(4.5);
        const hero = Math.min(contrast(t.heroTextPrimary, t.heroGradientStart, dark), contrast(t.heroTextPrimary, t.heroGradientEnd, dark));
        expect(hero, `${name} texte/héros`).toBeGreaterThanOrEqual(3);
        expect(contrast(t.onAccent, t.accent, dark), `${name} bouton`).toBeGreaterThanOrEqual(3);
      }
    }
  });
});
