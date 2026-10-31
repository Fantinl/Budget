# Budget pour Windows (Tauri)

Port complet de l'app Mac (`../Sources/Budget`) : mêmes pages, mêmes calculs, mêmes fichiers de données,
même synchronisation iCloud (`Budget-sync.json`). Interface en Svelte 5 + TypeScript, accès aux fichiers en Rust.
Règles de portage : [PORTAGE.md](PORTAGE.md).

Données :
- Windows : `%APPDATA%\Budget` ; synchro via le dossier iCloud Drive d'iCloud pour Windows (`%USERPROFILE%\iCloudDrive\Budget`) ;
- Mac (essais) : `~/Library/Application Support/Budget Proto`, distinct de l'app Mac.

```sh
npm install
npm run tauri dev                     # développement
npm run tauri build -- --bundles app  # app Mac (src-tauri/target/release/bundle/macos)
npm run check                         # types (svelte-check)
npm test                              # tests (vitest)
```

Non porté (propre au Mac) : icône de la barre des menus, raccourci global, mises à jour Sparkle.
