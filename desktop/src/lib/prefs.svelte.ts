// Préférences de l'interface (équivalent des @AppStorage / UserDefaults de l'app Mac), gardées en localStorage.
// Les données budgétaires, elles, sont dans les fichiers JSON (store.svelte.ts).

// Node (tests) peut exposer un localStorage inutilisable : on vérifie qu'il fonctionne.
const storage = typeof globalThis.localStorage?.getItem === "function" ? globalThis.localStorage : null;

function read<T>(key: string, fallback: T): T {
  try {
    const v = storage?.getItem(`pref:${key}`) ?? null;
    return v === null ? fallback : (JSON.parse(v) as T);
  } catch { return fallback; }
}

function write(key: string, value: unknown) {
  try { storage?.setItem(`pref:${key}`, JSON.stringify(value)); } catch { /* stockage indisponible */ }
}

/// Préférence réactive : `pref.value` se lit dans les composants et s'enregistre à l'affectation.
export class Pref<T> {
  #value: T;
  constructor(readonly key: string, fallback: T) { this.#value = $state(read(key, fallback)); }
  get value(): T { return this.#value; }
  set value(v: T) { this.#value = v; write(this.key, v); }
}

export type AppearanceMode = "system" | "light" | "dark";
export const appearanceLabel: Record<AppearanceMode, string> = { system: "Automatique", light: "Clair", dark: "Sombre" };

export const prefs = {
  /// Thème choisi (identifiant d'un thème de src/lib/theme.ts).
  themeID: new Pref("themeID", "minimal"),
  appearance: new Pref<AppearanceMode>("appearance", "system"),
  /// Assistant de démarrage terminé.
  onboardingCompleted: new Pref("onboardingCompleted", false),
  /// Profil étudiant : active le compte Izly et les repas Crous.
  studentProfile: new Pref("studentProfile", false),
  /// Regroupement de la page Comptes (« family » ou « bank »).
  accountsGrouping: new Pref("accountsGrouping", "family"),
  // Chiffres de la barre latérale (réglages → Apparence)
  sidebarFigures: new Pref("sidebarFigures", true),
  sidebarWealth: new Pref("sidebarFigures.wealth", true),
  sidebarSpent: new Pref("sidebarFigures.spent", true),
  sidebarIncome: new Pref("sidebarFigures.income", false),
  sidebarBalance: new Pref("sidebarFigures.balance", true),
  sidebarMonthCount: new Pref("sidebarFigures.monthCount", true),
  sidebarAccountCount: new Pref("sidebarFigures.accountCount", false),
};

/// Préférence libre (clé propre à une fonctionnalité : dernière vérification des taux, dossier de synchro…).
export function pref<T>(key: string, fallback: T): Pref<T> {
  return new Pref(key, fallback);
}
