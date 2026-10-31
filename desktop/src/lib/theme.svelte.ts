// Thèmes : port de Theme.swift. Chaque thème devient un jeu de variables CSS posées sur <html>
// (voir src/styles/base.css pour leurs noms). Les composants n'utilisent jamais de couleur en dur :
// ils lisent `var(--…)`. Les couleurs des catégories : `var(--cat-0)` … `var(--cat-11)`, repli `var(--cat-fallback)`
// (utiliser `categoryColor(index)`).

import { prefs } from "./prefs.svelte";

/// Couleur claire / sombre (équivalent de `Color(light:dark:)`).
export type Adaptive = string | { light: string; dark: string };

export interface Theme {
  id: string;
  name: string;
  background: Adaptive;
  surface: Adaptive;
  surfaceSecondary: Adaptive;
  separator: Adaptive;
  textPrimary: Adaptive;
  textSecondary: Adaptive;
  textTertiary: Adaptive;
  accent: Adaptive;
  positive: Adaptive;
  negative: Adaptive;
  warning: Adaptive;
  onAccent: Adaptive;
  categoryPalette: Adaptive[];   // 12 couleurs
  categoryFallback: Adaptive;
  // Typographie (tailles en px, graisses CSS)
  largeAmountSize: number;
  largeAmountWeight: number;
  amountWeight: number;
  titleWeight: number;
  captionWeight: number;
  rounded: boolean;
  /// Titres et montants en serif (thème Sable) ; le reste du texte garde la police du thème.
  serif?: boolean;
  // Formes et espacements (px)
  cornerRadius: number;
  smallCornerRadius: number;
  spacing: number;
  padding: number;
  iconSize: number;
  backgroundTop: Adaptive;
  backgroundBottom: Adaptive;
  /// Ombre CSS des cartes (« none » ou « 0 5px 14px rgba(…) »).
  cardShadow: Adaptive;
  cardBorder: Adaptive;
  cardBorderWidth: number;
  badgeFillOpacity: number;
  heroGradientStart: Adaptive;
  heroGradientEnd: Adaptive;
  heroTextPrimary: Adaptive;
  heroTextSecondary: Adaptive;
  heroShadow: Adaptive;
  /// Solde de la carte héros en vert/rouge (sinon en heroTextPrimary).
  heroTintsBalance: boolean;
}

/// `Color(white: x)` de SwiftUI.
export const white = (x: number, alpha = 1) => {
  const v = Math.round(x * 255);
  return alpha === 1 ? `rgb(${v}, ${v}, ${v})` : `rgba(${v}, ${v}, ${v}, ${alpha})`;
};

/// Style 1 — Minimal : fonds neutres, une seule couleur d'accent, palette de catégories douce.
export const minimal: Theme = {
  id: "minimal",
  name: "Minimal",
  background: { light: white(0.97), dark: white(0.07) },
  surface: { light: "#ffffff", dark: white(0.12) },
  surfaceSecondary: { light: white(0.94), dark: white(0.17) },
  separator: { light: white(0.90), dark: white(0.20) },
  textPrimary: { light: white(0.10), dark: white(0.95) },
  textSecondary: { light: white(0.45), dark: white(0.62) },
  textTertiary: { light: white(0.65), dark: white(0.42) },
  accent: "#2F6BFF",
  positive: "#1E9E6A",
  negative: "#E5484D",
  warning: "#E8A33D",
  onAccent: "#ffffff",
  categoryPalette: ["#5FB58A", "#B59A7A", "#5B8DEF", "#F0A04B", "#9B7FE6", "#E6787A",
                    "#E58BB8", "#6C7AE0", "#9AA0A6", "#3FB8A0", "#4FB3D9", "#7CC4C0"],
  categoryFallback: "#9AA0A6",
  largeAmountSize: 34,
  largeAmountWeight: 600,
  amountWeight: 500,
  titleWeight: 600,
  captionWeight: 400,
  rounded: true,
  cornerRadius: 16,
  smallCornerRadius: 8,
  spacing: 12,
  padding: 16,
  iconSize: 34,
  backgroundTop: { light: white(0.97), dark: white(0.07) },
  backgroundBottom: { light: white(0.97), dark: white(0.07) },
  cardShadow: "none",
  cardBorder: "transparent",
  cardBorderWidth: 0,
  badgeFillOpacity: 0.15,
  heroGradientStart: { light: "#ffffff", dark: white(0.12) },
  heroGradientEnd: { light: "#ffffff", dark: white(0.12) },
  heroTextPrimary: { light: white(0.10), dark: white(0.95) },
  heroTextSecondary: { light: white(0.45), dark: white(0.62) },
  heroShadow: "none",
  heroTintsBalance: true,
};


/// `Color(hex:)` avec opacité (`.opacity(a)`).
const rgba = (hex: number, a: number) => `rgba(${(hex >> 16) & 255}, ${(hex >> 8) & 255}, ${hex & 255}, ${a})`;
const hx = (n: number) => `#${n.toString(16).padStart(6, "0")}`;
const lightDark = (l: number | string, d: number | string): Adaptive => ({
  light: typeof l === "number" ? hx(l) : l, dark: typeof d === "number" ? hx(d) : d,
});
const shadow = (y: number, radius: number) => (c: string) => `0 ${y}px ${radius}px ${c}`;
const hexes = (...n: number[]) => n.map(hx);

/// Style 2 — Vivant : fond teinté en dégradé, accent violet affirmé, catégories saturées,
/// montants en gras, arrondis généreux, ombres douces, carte héros en dégradé.
export const vivid: Theme = {
  id: "vivid",
  name: "Vivant",
  background: lightDark(0xF5F2FF, 0x120F1C),
  surface: lightDark("#ffffff", 0x1D1A2A),
  surfaceSecondary: lightDark(0xEDE9FB, 0x2A2640),
  separator: lightDark(0xE3DEF5, 0x332F4A),
  textPrimary: lightDark(0x1A1530, 0xF4F1FF),
  textSecondary: lightDark(0x5E5878, 0xA9A3C4),
  textTertiary: lightDark(0x948EAD, 0x6F6A8A),
  accent: lightDark(0x6C47FF, 0x8F77FF),
  positive: lightDark(0x0FA968, 0x2FD68C),
  negative: lightDark(0xF03E5A, 0xFF6B80),
  warning: "#E8A33D",
  onAccent: "#ffffff",
  categoryPalette: hexes(0x22C07A, 0xC9894A, 0x2F7BFF, 0xFF8A1F, 0x8E5CF7, 0xFF4D5E, 0xF04FA0, 0x4B5CF0,
                         0x7C8798, 0x12B5A0, 0x1AA7E8, 0x36C9B8),
  categoryFallback: "#7C8798",
  largeAmountSize: 38, largeAmountWeight: 700, amountWeight: 700, titleWeight: 700, captionWeight: 500,
  rounded: true,
  cornerRadius: 22, smallCornerRadius: 12, spacing: 14, padding: 18, iconSize: 38,
  backgroundTop: lightDark(0xF3EEFF, 0x1A1430),
  backgroundBottom: lightDark(0xFFF3EC, 0x0F0D18),
  cardShadow: { light: shadow(5, 14)(rgba(0x4B2FB5, 0.12)), dark: shadow(5, 14)("rgba(0, 0, 0, 0.35)") },
  cardBorder: { light: "rgba(255, 255, 255, 0.8)", dark: "rgba(255, 255, 255, 0.06)" },
  cardBorderWidth: 1,
  badgeFillOpacity: 0.20,
  heroGradientStart: lightDark(0x6C47FF, 0x5B3BE0),
  heroGradientEnd: lightDark(0xC04DFF, 0xA03CD8),
  heroTextPrimary: "#ffffff",
  heroTextSecondary: "rgba(255, 255, 255, 0.78)",
  heroShadow: { light: shadow(5, 20)(rgba(0x6C47FF, 0.35)), dark: shadow(5, 20)("rgba(0, 0, 0, 0.45)") },
  heroTintsBalance: false,
};

/// Style 3 — Océan : bleus et turquoises, fond bleuté, héros en dégradé bleu → turquoise.
export const ocean: Theme = {
  id: "ocean",
  name: "Océan",
  background: lightDark(0xEEF6FA, 0x0A1620),
  surface: lightDark("#ffffff", 0x12212E),
  surfaceSecondary: lightDark(0xE1EEF5, 0x1B3042),
  separator: lightDark(0xD3E4EE, 0x244058),
  textPrimary: lightDark(0x0C2230, 0xEAF5FA),
  textSecondary: lightDark(0x4B6678, 0x9DB8C8),
  textTertiary: lightDark(0x82A0B2, 0x5F7E91),
  accent: lightDark(0x0A7F8C, 0x2CC4CF),
  positive: lightDark(0x0F9D6B, 0x34D399),
  negative: lightDark(0xE04F5F, 0xFF7385),
  warning: "#E8A33D",
  onAccent: lightDark("#ffffff", 0x06222B),
  categoryPalette: hexes(0x2DB87A, 0x7A6A5A, 0x2F80ED, 0xF29B38, 0x8E6CF0, 0xE5586B, 0xE87BB0, 0x4558D6,
                         0x8A9BA8, 0x14A89A, 0x2BB3E6, 0x6FD0C5),
  categoryFallback: "#8A9BA8",
  largeAmountSize: 36, largeAmountWeight: 600, amountWeight: 600, titleWeight: 600, captionWeight: 400,
  rounded: true,
  cornerRadius: 18, smallCornerRadius: 10, spacing: 12, padding: 16, iconSize: 36,
  backgroundTop: lightDark(0xE8F4FA, 0x0C1C2A),
  backgroundBottom: lightDark(0xF2FAF9, 0x08131B),
  cardShadow: { light: shadow(4, 10)(rgba(0x0A5A7A, 0.10)), dark: shadow(4, 10)("rgba(0, 0, 0, 0.35)") },
  cardBorder: { light: "rgba(255, 255, 255, 0.9)", dark: "rgba(255, 255, 255, 0.05)" },
  cardBorderWidth: 1,
  badgeFillOpacity: 0.18,
  heroGradientStart: lightDark(0x1C6FD1, 0x15509E),
  heroGradientEnd: lightDark(0x0E9A9A, 0x0C7F85),
  heroTextPrimary: "#ffffff",
  heroTextSecondary: "rgba(255, 255, 255, 0.82)",
  heroShadow: { light: shadow(4, 18)(rgba(0x1C6FD1, 0.30)), dark: shadow(4, 18)("rgba(0, 0, 0, 0.45)") },
  heroTintsBalance: false,
};

/// Style 4 — Forêt : verts sauge et mousse, bois clair, accent vert sapin.
export const forest: Theme = {
  id: "forest",
  name: "Forêt",
  background: lightDark(0xF1F3EC, 0x10150F),
  surface: lightDark(0xFAFBF6, 0x1A211A),
  surfaceSecondary: lightDark(0xE5E9DC, 0x252E24),
  separator: lightDark(0xD8DECD, 0x303B2E),
  textPrimary: lightDark(0x1B2A1C, 0xEDF2E6),
  textSecondary: lightDark(0x566652, 0xA3B39D),
  textTertiary: lightDark(0x8A9885, 0x68775F),
  accent: lightDark(0x2E6B4A, 0x6FBF8E),
  positive: lightDark(0x2E8B57, 0x5BCB8A),
  negative: lightDark(0xC8483E, 0xF07A6E),
  warning: "#D9962B",
  onAccent: lightDark("#ffffff", 0x0E2417),
  categoryPalette: hexes(0x5FA86A, 0xA0825A, 0x4A86B5, 0xE09A3E, 0x8C6BB5, 0xCB5A4C, 0xD9799B, 0x5D6FBF,
                         0x8E9A8A, 0x2F9E7E, 0x5BAFC4, 0xA6B84A),
  categoryFallback: "#8E9A8A",
  largeAmountSize: 34, largeAmountWeight: 600, amountWeight: 500, titleWeight: 600, captionWeight: 400,
  rounded: true,
  cornerRadius: 16, smallCornerRadius: 9, spacing: 12, padding: 16, iconSize: 34,
  backgroundTop: lightDark(0xF1F3EC, 0x10150F),
  backgroundBottom: lightDark(0xE9EEE2, 0x0C100B),
  cardShadow: { light: shadow(3, 8)(rgba(0x2E4A33, 0.08)), dark: shadow(3, 8)("rgba(0, 0, 0, 0.30)") },
  cardBorder: { light: rgba(0xD8DECD, 0.7), dark: "rgba(255, 255, 255, 0.04)" },
  cardBorderWidth: 1,
  badgeFillOpacity: 0.18,
  heroGradientStart: lightDark(0x1F4D36, 0x17402D),
  heroGradientEnd: lightDark(0x3C7A55, 0x2F6446),
  heroTextPrimary: "#ffffff",
  heroTextSecondary: "rgba(255, 255, 255, 0.80)",
  heroShadow: { light: shadow(3, 16)(rgba(0x1F4D36, 0.28)), dark: shadow(3, 16)("rgba(0, 0, 0, 0.45)") },
  heroTintsBalance: false,
};

/// Style 5 — Sable : terre, terracotta et crème, ambiance papier, titres et montants en serif.
export const sand: Theme = {
  id: "sand",
  name: "Sable",
  background: lightDark(0xF6EFE4, 0x1A1511),
  surface: lightDark(0xFFFAF2, 0x241D17),
  surfaceSecondary: lightDark(0xEDE3D3, 0x30271F),
  separator: lightDark(0xE2D6C2, 0x3D3228),
  textPrimary: lightDark(0x2E2118, 0xF4EBDD),
  textSecondary: lightDark(0x6B5846, 0xBBA98F),
  textTertiary: lightDark(0x9C8A74, 0x85755F),
  accent: lightDark(0xB5522F, 0xE2845E),
  positive: lightDark(0x4F8A4B, 0x8CC27F),
  negative: lightDark(0xB83A3A, 0xF08080),
  warning: "#D99A2B",
  onAccent: lightDark("#ffffff", 0x2A140A),
  categoryPalette: hexes(0x7E9A5B, 0xA67C52, 0x4F7FA8, 0xE0933C, 0x8A6BA8, 0xC8553D, 0xD97B9A, 0x5E6BB0,
                         0x9A8F82, 0x3E9A87, 0x5AA7C2, 0xB8B34A),
  categoryFallback: "#9A8F82",
  largeAmountSize: 36, largeAmountWeight: 600, amountWeight: 600, titleWeight: 600, captionWeight: 400,
  rounded: true,
  serif: true,
  cornerRadius: 14, smallCornerRadius: 8, spacing: 12, padding: 16, iconSize: 34,
  backgroundTop: lightDark(0xF8F1E6, 0x1C1712),
  backgroundBottom: lightDark(0xF2E8D8, 0x16120E),
  cardShadow: { light: shadow(3, 8)(rgba(0x7A5230, 0.10)), dark: shadow(3, 8)("rgba(0, 0, 0, 0.30)") },
  cardBorder: { light: hx(0xE2D6C2), dark: "rgba(255, 255, 255, 0.05)" },
  cardBorderWidth: 1,
  badgeFillOpacity: 0.20,
  heroGradientStart: lightDark(0xA84A28, 0x8F3E20),
  heroGradientEnd: lightDark(0xB86A35, 0xA55A2C),
  heroTextPrimary: "#ffffff",
  heroTextSecondary: "rgba(255, 255, 255, 0.85)",
  heroShadow: { light: shadow(3, 16)(rgba(0xA84A28, 0.28)), dark: shadow(3, 16)("rgba(0, 0, 0, 0.45)") },
  heroTintsBalance: false,
};

/// Style 6 — Contraste : noir et blanc nets, accent orange / jaune vif, sans ombres, bordures marquées.
export const contrast: Theme = {
  id: "contrast",
  name: "Contraste",
  background: lightDark("#ffffff", "#000000"),
  surface: lightDark("#ffffff", 0x0D0D0D),
  surfaceSecondary: lightDark(0xEDEDED, 0x262626),
  separator: lightDark("#000000", "#ffffff"),
  textPrimary: lightDark("#000000", "#ffffff"),
  textSecondary: lightDark(0x333333, 0xD9D9D9),
  textTertiary: lightDark(0x595959, 0xB3B3B3),
  accent: lightDark(0xC2410C, 0xFFD60A),
  positive: lightDark(0x006B2E, 0x4DFF88),
  negative: lightDark(0xB00020, 0xFF6B6B),
  warning: lightDark(0xB85C00, 0xFFB000),
  onAccent: lightDark("#ffffff", "#000000"),
  categoryPalette: hexes(0x00A651, 0x8B5A2B, 0x0057E7, 0xFF8000, 0x8000FF, 0xE60026, 0xFF3399, 0x2B2BCC,
                         0x707070, 0x00A89D, 0x00AEEF, 0x99CC00),
  categoryFallback: "#707070",
  largeAmountSize: 38, largeAmountWeight: 800, amountWeight: 700, titleWeight: 800, captionWeight: 600,
  rounded: false,
  cornerRadius: 10, smallCornerRadius: 6, spacing: 12, padding: 16, iconSize: 36,
  backgroundTop: lightDark("#ffffff", "#000000"),
  backgroundBottom: lightDark("#ffffff", "#000000"),
  cardShadow: "none",
  cardBorder: lightDark("#000000", "#ffffff"),
  cardBorderWidth: 1.5,
  badgeFillOpacity: 0.30,
  heroGradientStart: lightDark("#000000", 0xFFD60A),
  heroGradientEnd: lightDark(0x222222, 0xFFB000),
  heroTextPrimary: lightDark("#ffffff", "#000000"),
  heroTextSecondary: { light: "rgba(255, 255, 255, 0.88)", dark: "rgba(0, 0, 0, 0.8)" },
  heroShadow: "none",
  heroTintsBalance: false,
};

/// Thèmes proposés dans les réglages (Theme.all).
export const themes: Theme[] = [minimal, vivid, ocean, forest, sand, contrast];

export const themeNamed = (id: string) => themes.find(t => t.id === id) ?? minimal;

const pick = (c: Adaptive, dark: boolean) => (typeof c === "string" ? c : dark ? c.dark : c.light);

/// Pose les variables CSS du thème sur <html> pour le mode clair ou sombre.
export function applyTheme(theme: Theme, dark: boolean) {
  const vars: Record<string, string> = {
    "--background": pick(theme.background, dark),
    "--surface": pick(theme.surface, dark),
    "--surface-secondary": pick(theme.surfaceSecondary, dark),
    "--separator": pick(theme.separator, dark),
    "--text-primary": pick(theme.textPrimary, dark),
    "--text-secondary": pick(theme.textSecondary, dark),
    "--text-tertiary": pick(theme.textTertiary, dark),
    "--accent": pick(theme.accent, dark),
    "--positive": pick(theme.positive, dark),
    "--negative": pick(theme.negative, dark),
    "--warning": pick(theme.warning, dark),
    "--on-accent": pick(theme.onAccent, dark),
    "--cat-fallback": pick(theme.categoryFallback, dark),
    "--large-amount-size": `${theme.largeAmountSize}px`,
    "--large-amount-weight": String(theme.largeAmountWeight),
    "--amount-weight": String(theme.amountWeight),
    "--title-weight": String(theme.titleWeight),
    "--caption-weight": String(theme.captionWeight),
    "--font": theme.rounded
      ? `ui-rounded, "SF Pro Rounded", "Segoe UI Variable Display", "Segoe UI", system-ui, sans-serif`
      : `system-ui, -apple-system, "Segoe UI Variable Text", "Segoe UI", sans-serif`,
    "--font-display": theme.serif ? `ui-serif, "New York", Georgia, "Cambria", serif` : "inherit",
    "--radius": `${theme.cornerRadius}px`,
    "--radius-small": `${theme.smallCornerRadius}px`,
    "--spacing": `${theme.spacing}px`,
    "--padding": `${theme.padding}px`,
    "--icon-size": `${theme.iconSize}px`,
    "--bg-top": pick(theme.backgroundTop, dark),
    "--bg-bottom": pick(theme.backgroundBottom, dark),
    "--card-shadow": pick(theme.cardShadow, dark),
    "--card-border": pick(theme.cardBorder, dark),
    "--card-border-width": `${theme.cardBorderWidth}px`,
    "--badge-opacity": String(theme.badgeFillOpacity),
    "--hero-start": pick(theme.heroGradientStart, dark),
    "--hero-end": pick(theme.heroGradientEnd, dark),
    "--hero-text-primary": pick(theme.heroTextPrimary, dark),
    "--hero-text-secondary": pick(theme.heroTextSecondary, dark),
    "--hero-shadow": pick(theme.heroShadow, dark),
  };
  theme.categoryPalette.forEach((c, i) => { vars[`--cat-${i}`] = pick(c, dark); });
  const root = document.documentElement;
  for (const [k, v] of Object.entries(vars)) root.style.setProperty(k, v);
  root.dataset.theme = theme.id;
  root.dataset.scheme = dark ? "dark" : "light";
  root.style.colorScheme = dark ? "dark" : "light";
}

/// Couleur CSS d'un index de palette (catégorie, compte, tag) ; hors palette → couleur de repli.
export function categoryColor(index: number): string {
  return index >= 0 && index < 12 ? `var(--cat-${index})` : "var(--cat-fallback)";
}

/// Le thème courant tient-il à colorer le solde de la carte héros ?
export const currentTheme = () => themeNamed(prefs.themeID.value);

/// Suit le thème et l'apparence choisis (et le mode du système en « Automatique »).
export function startTheming() {
  const media = window.matchMedia("(prefers-color-scheme: dark)");
  const update = () => {
    const mode = prefs.appearance.value;
    applyTheme(currentTheme(), mode === "dark" || (mode === "system" && media.matches));
  };
  media.addEventListener("change", update);
  $effect.root(() => { $effect(update); });
}
