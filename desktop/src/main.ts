// Démarrage : dossiers, chargement des données, thème, puis affichage.
import { mount } from "svelte";
import "./styles/base.css";
import App from "./App.svelte";
import { setStore } from "./lib/app.svelte";
import { loadPaths } from "./lib/platform";
import { BudgetStore } from "./lib/store.svelte";
import { startTheming } from "./lib/theme.svelte";

async function start() {
  startTheming();
  const paths = await loadPaths();
  const store = new BudgetStore(paths.dataDir);
  await store.reloadFromDisk();
  setStore(store);
  mount(App, { target: document.getElementById("app")! });
}

void start();
