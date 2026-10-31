// Vérifie que les pages Tableau de bord, Budget et Statistiques s'affichent (rendu serveur) avec des données.
import { describe, expect, it } from "vitest";
import { render } from "svelte/server";
import { makeStore, expense, income } from "../lib/test/support";
import { setStore } from "../lib/app.svelte";
import DashboardPage from "./dashboard/DashboardPage.svelte";
import PlanningPage from "./planning/PlanningPage.svelte";
import StatsView from "./stats/StatsView.svelte";

describe("pages", () => {
  it("s'affichent avec des données", async () => {
    const s = await makeStore();
    const now = new Date();
    s.upsertCategory({ ...s.category("restaurants"), monthlyBudgetCents: 20000, budgetRollover: true });
    s.upsertCategory({ ...s.category("groceries"), monthlyBudgetCents: 30000 });
    for (let m = 0; m < 5; m++) {
      const d = new Date(now.getFullYear(), now.getMonth() - m, 5, 12);
      s.upsert(expense(80 + m * 10, "restaurants", d));
      s.upsert(expense(120, "groceries", d));
      s.upsert(income(1500, d));
    }
    setStore(s);
    const dash = render(DashboardPage).body;
    expect(dash).toContain("Argent disponible");
    expect(dash).toContain("Budgets");
    const plan = render(PlanningPage).body;
    expect(plan).toContain("Plan du mois");
    expect(plan).toContain("Enveloppes");
    expect(plan).toContain("Équilibre");
    const stats = render(StatsView).body;
    expect(stats).toContain("Par catégorie");
    expect(stats).toContain("Évolution mensuelle");
  });

  it("s'affichent sans données", async () => {
    setStore(await makeStore());
    expect(render(DashboardPage).body).toContain("Aucune opération.");
    expect(render(PlanningPage).body).toContain("Aucun budget");
    expect(render(StatsView).body).toContain("Aucune donnée");
  });
});
