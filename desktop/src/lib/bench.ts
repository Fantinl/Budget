// Mode mesure (variable d'environnement BUDGET_BENCH_DIR) : mêmes mesures que la copie de mesure de l'app Mac
// — temps d'affichage de chaque page et durée des calculs principaux — écrites dans results-tauri.json.

import { tick } from "svelte";
import type { Page } from "./app.svelte";
import { BudgetStore } from "./store.svelte";
import { join, writeText } from "./platform";
import { makeDashboardSummary } from "./logic/dashboard";
import { budgetStatuses } from "./logic/budgets";
import { annualBudgetBalance } from "./logic/planning";
import { makeStatsSnapshot } from "./logic/stats";
import { foldText } from "./logic/filter";

const median = (v: number[]) => [...v].sort((a, b) => a - b)[Math.floor(v.length / 2)];

/// Après l'affichage : deux images (la page est peinte).
const nextFrame = () => new Promise<void>(r => requestAnimationFrame(() => requestAnimationFrame(() => r())));

/// Durée moyenne d'un appel sur `n` appels (l'horloge de WebKit n'est précise qu'à la milliseconde).
function time(n: number, body: () => void): number {
  body();   // échauffement
  const t0 = performance.now();
  for (let i = 0; i < n; i++) body();
  return (performance.now() - t0) / n;
}

async function timeAsync(n: number, body: () => Promise<void>): Promise<number> {
  const samples: number[] = [];
  for (let i = 0; i < n; i++) { const t0 = performance.now(); await body(); samples.push(performance.now() - t0); }
  return median(samples);
}

/// Calculs principaux, communs à l'app (WebKit / WebView2) et à Node.
export async function logicBench(s: BudgetStore, dir: string): Promise<Record<string, number>> {
  const now = new Date();
  const logic: Record<string, number> = {};
  logic.dashboard = time(50, () => { makeDashboardSummary(s, now); });
  logic.monthList = time(500, () => { s.transactionsInMonthOf(now); });
  logic.search = time(100, () => {
    const q = foldText("caf");
    s.transactions.filter(t => foldText(t.note).includes(q) || foldText(s.categoryOf(t).label).includes(q));
  });
  logic.budgets = time(200, () => { budgetStatuses(s, now); });
  logic.annual = time(50, () => { annualBudgetBalance(s, now, now); });
  logic.statsYear = time(50, () => { makeStatsSnapshot(s.transactions, "year", 0, id => s.category(id), now); });
  logic.statsAll = time(20, () => { makeStatsSnapshot(s.transactions, "all", 0, id => s.category(id), now); });
  logic.save = await timeAsync(5, async () => { s.saveTransactions(); await s.flush(); });
  logic.load = await timeAsync(3, async () => { await new BudgetStore(dir).reloadFromDisk(); });
  return logic;
}

export async function runBench(s: BudgetStore, dir: string, select: (page: Page) => void, pageStart: number) {
  await nextFrame();
  const result: Record<string, unknown> = { ready: performance.timeOrigin + performance.now(), startupInPage: performance.now() - pageStart, count: s.transactions.length };
  const pages: Page[] = ["operations", "accounts", "planning", "stats", "dashboard"];
  // « prête » = DOM à jour et mise en page calculée ; « peinte » = deux images plus tard (calé sur l'écran).
  const ready: Record<string, number[]> = {};
  const painted: Record<string, number[]> = {};
  for (let round = 0; round < 7; round++) {
    for (const page of pages) {
      const t0 = performance.now();
      select(page);
      await tick();
      void document.body.getBoundingClientRect();   // force la mise en page
      (ready[page] ??= []).push(performance.now() - t0);
      await nextFrame();
      (painted[page] ??= []).push(performance.now() - t0);
    }
  }
  // 1er tour = échauffement
  const medians = (m: Record<string, number[]>) => Object.fromEntries(Object.entries(m).map(([k, v]) => [k, median(v.slice(1))]));
  result.pages = medians(ready);
  result.pagesPainted = medians(painted);
  // Repère pour le relevé de la mémoire (fait par le script de mesure), avant les calculs qui rechargent les données.
  await writeText(join(dir, "pages-done"), "1");
  await new Promise(r => setTimeout(r, 2000));
  result.logic = await logicBench(s, dir);
  const memory = (performance as unknown as { memory?: { usedJSHeapSize: number } }).memory;
  if (memory) result.jsHeapMB = memory.usedJSHeapSize / 1_048_576;
  await writeText(join(dir, "results-tauri.json"), JSON.stringify(result, null, 2));
}
