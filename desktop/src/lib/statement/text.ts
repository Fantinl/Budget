// Aides de texte communes à la lecture des relevés.

/// Équivalent de `CharacterSet.whitespaces` : tabulation et espaces (catégorie Zs), sans retours à la ligne.
const SPACES = "\\t\\u0020\\u00A0\\u1680\\u2000-\\u200A\\u202F\\u205F\\u3000";
const trimSpacesRegex = new RegExp(`^[${SPACES}]+|[${SPACES}]+$`, "g");
export const trimSpaces = (s: string) => s.replace(trimSpacesRegex, "");

/// Équivalent de `Character.isWhitespace` + espace insécable.
export const WHITESPACE_RUN = /[\s ]+/;

/// Réduit les espaces multiples, nettoie les extrémités.
export function collapseSpaces(text: string): string {
  return text.split(WHITESPACE_RUN).filter(w => w.length > 0).join(" ");
}

/// Minuscules, sans accents, espaces réduits.
export function normalize(text: string): string {
  return collapseSpaces(text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase());
}

// MARK: - Nombres décimaux exacts (le `Decimal` de Swift) en centimes

/// Décompose « 12.345 » ou « 1.2E2 » : signe, chiffres, position de la virgule. null si ce n'est pas un nombre.
function splitDecimal(raw: string): { negative: boolean; int: string; frac: string } | null {
  const m = /^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$/.exec(raw.trim());
  if (!m) return null;
  let int = m[2], frac = m[3] ?? "";
  if (int.length + frac.length === 0) return null;
  const exp = m[4] ? Number(m[4]) : 0;
  if (!Number.isFinite(exp) || Math.abs(exp) > 400) return null;
  if (exp > 0) {
    const all = int + frac;
    const point = int.length + exp;
    int = all.slice(0, point).padEnd(point, "0");
    frac = all.slice(point);
  } else if (exp < 0) {
    const all = int + frac;
    const point = int.length + exp;
    if (point <= 0) { int = ""; frac = "0".repeat(-point) + all; } else { int = all.slice(0, point); frac = all.slice(point); }
  }
  return { negative: m[1] === "-", int, frac };
}

/// Texte décimal → centimes entiers, arrondis « au plus proche, 0,5 vers l'extérieur » (`NSDecimalRound .plain`).
export function decimalStringToCents(raw: string): number | null {
  const d = splitDecimal(raw);
  if (!d) return null;
  const int = d.int === "" ? 0 : Number(d.int);
  const frac = (d.frac + "000").slice(0, 3);
  let cents = int * 100 + Number(frac.slice(0, 2));
  if (Number(frac[2]) >= 5) cents += 1;
  return d.negative ? -cents : cents;
}

/// Centimes → texte décimal minimal (« 1234.56 », « 120 », « 12.3 »), comme `NSDecimalNumber.stringValue`.
export function centsToDecimalString(cents: number): string {
  const sign = cents < 0 ? "-" : "";
  const abs = Math.abs(cents);
  const int = Math.floor(abs / 100);
  const frac = String(abs % 100).padStart(2, "0").replace(/0+$/, "");
  return sign + int + (frac ? "." + frac : "");
}
