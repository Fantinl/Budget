// Calendrier, dans le fuseau local (équivalent de `Calendar.current` de l'app Mac).

export const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
export const startOfMonth = (d: Date) => new Date(d.getFullYear(), d.getMonth(), 1);
export const startOfYear = (d: Date) => new Date(d.getFullYear(), 0, 1);
export const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());

/// Comme `Calendar.date(byAdding: .month)` : le jour est borné au dernier jour du mois d'arrivée.
export function addMonths(d: Date, n: number): Date {
  const target = new Date(d.getFullYear(), d.getMonth() + n, 1, d.getHours(), d.getMinutes(), d.getSeconds(), d.getMilliseconds());
  target.setDate(Math.min(d.getDate(), daysInMonth(target)));
  return target;
}

export const daysInMonth = (d: Date) => new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();

/// Intervalle du mois [début, fin[ — fin exclue : une opération à minuit le 1er n'appartient qu'au nouveau mois.
export function monthInterval(d: Date): { start: Date; end: Date } {
  const start = startOfMonth(d);
  return { start, end: new Date(start.getFullYear(), start.getMonth() + 1, 1) };
}

export function isInMonth(date: Date, month: Date): boolean {
  return date.getFullYear() === month.getFullYear() && date.getMonth() === month.getMonth();
}

export const isSameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
export const isToday = (d: Date, now = new Date()) => isSameDay(d, now);

/// Clé d'un mois (« 2026-10 »), utilisée par les budgets propres à un mois.
export function monthKey(d: Date): string {
  return `${String(d.getFullYear()).padStart(4, "0")}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

/// Jour de la semaine au format Swift : 1 = dimanche … 7 = samedi.
export const weekday = (d: Date) => d.getDay() + 1;

/// Nombre de jours entiers entre deux débuts de journée (b − a).
export function daysBetween(a: Date, b: Date): number {
  return Math.round((startOfDay(b).getTime() - startOfDay(a).getTime()) / 86_400_000);
}

/// Date d'un champ <input type="date"> (« 2026-10-30 ») → minuit local.
export function fromInputDate(value: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null;
}

export function toInputDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
