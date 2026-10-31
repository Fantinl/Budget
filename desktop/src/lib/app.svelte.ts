// État global de l'app : le magasin unique et la navigation (équivalent de RootView.selection).

import type { BudgetStore } from "./store.svelte";

/// Le magasin, créé et chargé au démarrage (main.ts) avant l'affichage. À importer partout : `import { store } from "…/app.svelte"`.
export let store: BudgetStore;

export function setStore(s: BudgetStore) { store = s; }

/// Sections de la barre latérale (SidebarItem.swift).
export type Page = "dashboard" | "operations" | "accounts" | "planning" | "stats";

export const nav = $state({
  page: "dashboard" as Page,
  /// Compte ouvert sur la page Comptes (détail d'un compte), null = liste des comptes.
  accountID: null as string | null,
  /// Réglages affichés (fenêtre Réglages de l'app Mac).
  settingsOpen: false,
  /// Section des réglages à ouvrir (identifiant libre défini par la page Réglages), null = accueil des réglages.
  settingsSection: null as string | null,
});

/// Aller à une page (cartes du tableau de bord, liens…).
export function navigate(page: Page, options: { accountID?: string | null } = {}) {
  nav.page = page;
  nav.accountID = options.accountID ?? null;
}

export function openSettings(section: string | null = null) {
  nav.settingsSection = section;
  nav.settingsOpen = true;
}
