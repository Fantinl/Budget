// État réactif des taux réglementés (lu par les cartes de compte, mis à jour par le téléchargement).
// Séparé de rates.ts parce que les runes ne fonctionnent que dans un fichier `.svelte.ts`.

export interface RateEntry { rate: number; since: string; verified?: boolean | null; note?: string | null }
export interface PELEntry { from: string; rate: number; verified?: boolean | null }

export interface RateTable {
  version: number;
  updatedAt: string;
  source: string;
  rates: Record<string, RateEntry>;
  pel: PELEntry[];
}

/// Copie embarquée : doit rester identique à `rates.json` à la racine du dépôt.
export const embeddedRates: RateTable = {
  version: 1,
  updatedAt: "2026-10-17",
  source: "Journal officiel (arrêté du 28 juillet 2026)",
  rates: {
    livretA: { rate: 1.7, since: "2026-08-01", verified: true },
    ldds: { rate: 1.7, since: "2026-08-01", verified: true },
    lep: { rate: 2.5, since: "2026-08-01", verified: true },
    livretJeune: { rate: 1.7, since: "2026-08-01", verified: false },
    cel: { rate: 1.25, since: "2026-08-01", verified: false },
  },
  pel: [
    { from: "2016-02-01", rate: 1.5, verified: true },
    { from: "2016-08-01", rate: 1.0, verified: true },
    { from: "2023-01-01", rate: 2.0, verified: false },
    { from: "2024-01-01", rate: 2.25, verified: false },
    { from: "2025-01-01", rate: 1.75, verified: true },
    { from: "2026-01-01", rate: 2.0, verified: true },
  ],
};

export const rateState = $state({ table: embeddedRates, cacheLoaded: false });
