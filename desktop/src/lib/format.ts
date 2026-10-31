// Formats d'affichage en français (équivalents de `Decimal.euros` et des `Date.FormatStyle` de l'app Mac).

const eurosFormat = new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR" });
const roundEurosFormat = new Intl.NumberFormat("fr-FR", { style: "currency", currency: "EUR", maximumFractionDigits: 0, minimumFractionDigits: 0 });
const numberFormat = new Intl.NumberFormat("fr-FR", { maximumFractionDigits: 2 });

/// 123456 → « 1 234,56 € ».
export const euros = (cents: number) => eurosFormat.format(cents / 100);
/// Sans centimes (barre latérale) : « 1 235 € ».
export const roundEuros = (cents: number) => roundEurosFormat.format(cents / 100);
/// Montant avec signe explicite (« +12,00 € », « −3,50 € »).
export const signedEuros = (cents: number) => (cents > 0 ? "+" : "") + euros(cents);
/// Montant à mettre dans un champ texte (« 12,5 »).
export const amountInput = (cents: number) => numberFormat.format(cents / 100).replace(/\s/g, "");
export const percent = (ratio: number, digits = 0) =>
  new Intl.NumberFormat("fr-FR", { style: "percent", maximumFractionDigits: digits }).format(ratio);

/// Montant saisi (« 12,50 », « 12.5 », « 1 234 ») → centimes, null si invalide.
export function parseAmount(text: string): number | null {
  const clean = text.replace(/[\s  €]/g, "").replace(",", ".");
  if (!/^-?\d+(\.\d+)?$/.test(clean)) return null;
  return Math.round(Number(clean) * 100);
}

const fmt = (options: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat("fr-FR", options);
const dayMonth = fmt({ day: "numeric", month: "short" });
const dayMonthYear = fmt({ day: "numeric", month: "short", year: "numeric" });
const longDate = fmt({ weekday: "long", day: "numeric", month: "long" });
const monthYear = fmt({ month: "long", year: "numeric" });
const monthShort = fmt({ month: "short" });
const monthLong = fmt({ month: "long" });
const time = fmt({ hour: "2-digit", minute: "2-digit" });

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/// « 12 oct. »
export const shortDate = (d: Date) => dayMonth.format(d);
/// « 12 oct. 2026 »
export const mediumDate = (d: Date) => dayMonthYear.format(d);
/// « Vendredi 30 octobre »
export const longDayDate = (d: Date) => capitalize(longDate.format(d));
/// « Octobre 2026 »
export const monthTitle = (d: Date) => capitalize(monthYear.format(d));
/// « oct. »
export const monthAbbrev = (d: Date) => monthShort.format(d);
/// « Octobre »
export const monthName = (d: Date) => capitalize(monthLong.format(d));
/// « 14:05 »
export const timeOfDay = (d: Date) => time.format(d);
