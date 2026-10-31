# Portage de l'app Mac vers Tauri (Windows)

L'app Mac (SwiftUI, `../Sources/Budget`) est la référence : mêmes fonctionnalités, mêmes textes, mêmes calculs,
mêmes fichiers. Ce dossier en est le port en Svelte 5 + TypeScript (interface et logique) et Rust (accès aux fichiers).

## Organisation

| Swift | Tauri |
|---|---|
| `Models.swift` | `src/lib/model.ts` (types, valeurs par défaut) et `src/lib/codec.ts` (JSON) |
| `BudgetStore.swift` (+Undo, +Sync) | `src/lib/store.svelte.ts` |
| `BudgetStore+X.swift` | `src/lib/logic/x.ts` : fonctions `f(s: BudgetStore, …)` |
| `SyncMetadata.swift` | `src/lib/sync/tracker.ts` |
| `Theme.swift` | `src/lib/theme.svelte.ts` (variables CSS) + `src/styles/base.css` |
| `@AppStorage` | `src/lib/prefs.svelte.ts` |
| `RootView`, `SidebarView` | `src/App.svelte`, `src/Sidebar.svelte` |
| vues d'une page | `src/pages/<page>/*.svelte` |
| composants communs | `src/ui/*.svelte` |
| accès disque, dialogues | `src/lib/platform.ts` → commandes de `src-tauri/src/lib.rs` |

## Règles

- **Données** : montants en centimes entiers (`…Cents`), dates en `Date` locales. Jamais de flottant pour un montant
  (sauf affichage et lecture/écriture JSON, faites par `codec.ts`). Calendrier : `src/lib/dates.ts` (fuseau local,
  intervalle de mois semi-ouvert : une opération à minuit le 1er n'appartient qu'au nouveau mois).
- **Modifications** : les tableaux du magasin sont en `$state.raw` → on les remplace, on ne les modifie jamais en place
  (`s.transactions = s.transactions.map(…)`), et les enregistrements sont remplacés (`{ ...t, note }`).
  Une action utilisateur = `s.registerUndo("Libellé exact de l'app Mac")`, puis la modification, puis
  `s.saveTransactions()` / `s.saveSettings()`. La synchro est suivie automatiquement à l'enregistrement.
- **Accès au magasin** : `import { store } from "../../lib/app.svelte"` ; navigation : `navigate(page, { accountID })`,
  `openSettings(section)`.
- **Interface** : Svelte 5 (runes : `$state`, `$derived`, `$props`, `$effect`). Couleurs, tailles et rayons uniquement
  via les variables CSS du thème (`var(--accent)`, `var(--radius)`…) et les classes de `base.css` (`.btn`, `.field`,
  `.caption`, `.amount`, `.large-amount`, `.grid`, `.line`, `.segmented`, `.switch`, `.gauge`…).
  Composants : `Card` (et `hero`), `Sheet` (feuilles modales), `Icon` (nom de symbole SF), `CategoryBadge`,
  `AccountBadge`, `TransactionRow`, `DateField`, `MonthPicker`. Couleur d'une catégorie/compte : `categoryColor(index)`.
  Nouvelles icônes SF → les ajouter à `src/ui/icons.ts`.
- **Textes** : identiques à l'app Mac (français, apostrophes typographiques ’ comme dans le Swift).
  Formats : `src/lib/format.ts` (`euros`, `shortDate`…).
- **Confirmations** : `confirmDialog()` de `platform.ts` (boîte native). Fichiers : `chooseFile`, `chooseSaveFile`,
  `readText`, `writeText`, `readBytes`.
- **Raccourcis** : ⌘ sur Mac = Ctrl sur Windows (`e.metaKey || e.ctrlKey`).
- **Spécifique Mac non porté** : barre des menus (MenuBarPanel), raccourci global (GlobalHotKey), Sparkle (Updater),
  signets « security-scoped ». Le reste est porté.
- **Tests** : `npm test` (vitest). Porter les tests Swift correspondants (`../Tests/BudgetTests`) dans
  `src/lib/logic/*.test.ts` ; aides dans `src/lib/test/support.ts` (`makeStore`, `day`, `expense`, `income`, `tick`).
- **Vérifications** : `npm run check` (svelte-check, 0 erreur, 0 avertissement) et `npm test`.
- **Dépendances** : éviter ; si indispensable, version exacte publiée depuis plus de deux semaines.
- **Données réelles** : sur le Mac, l'app utilise son propre dossier (`~/Library/Application Support/Budget Proto`) ;
  ne jamais écrire dans les dossiers de l'app Mac ni dans iCloud pendant le développement.
