<script lang="ts">
  // Assistant de démarrage : compte par défaut, récurrentes et ajouts rapides. Port de OnboardingView.swift.
  // Plein écran au-dessus de l'app. Seuls les comptes ajoutés via l'éditeur sont enregistrés avant « Commencer ».
  import { fly } from "svelte/transition";
  import { store } from "../../lib/app.svelte";
  import { prefs } from "../../lib/prefs.svelte";
  import { MAIN_ACCOUNT_ID, mainAccount, newID } from "../../lib/model";
  import { currentTheme } from "../../lib/theme.svelte";
  import { makeIzly, upsertAccount } from "../../lib/logic/accounts";
  import { upsertRecurring } from "../../lib/logic/recurring";
  import { type AccountDraft, draftFrom, isBlank, parseDecimal, validated } from "../accounts/accountDraft";
  import Card from "../../ui/Card.svelte";
  import Icon from "../../ui/Icon.svelte";
  import Sheet from "../../ui/Sheet.svelte";
  import SyncSettings from "../settings/SyncSettings.svelte";
  import StepHeader from "./StepHeader.svelte";
  import StudentStep from "./StudentStep.svelte";
  import AccountStep from "./AccountStep.svelte";
  import RecurringStep from "./RecurringStep.svelte";
  import QuickStep from "./QuickStep.svelte";
  import {
    type QuickItem, type RecurringItem, count, crousItem, existingQuickItem, itemAmount, itemDay, nextDate, quickSuggestions,
    quickValid, recurringSuggestions, recurringValid, toQuickExpense,
  } from "./items";

  let { onfinish }: { onfinish: () => void } = $props();

  const steps = ["welcome", "student", "account", "recurring", "quick", "done"] as const;
  type Step = (typeof steps)[number];

  let stepIndex = $state(0);
  let goingForward = $state(true);
  const step = $derived<Step>(steps[stepIndex]);

  // « J'utilise déjà Budget sur un autre appareil » : réglages de synchronisation dans une feuille.
  let showSync = $state(false);

  // Reprend l'état actuel du magasin (compte principal, récurrentes, ajouts rapides).
  const main = store.account(MAIN_ACCOUNT_ID);
  const initialDraft = draftFrom(main);
  initialDraft.nameIsAuto = main.name === mainAccount().name;
  let draft = $state<AccountDraft>(initialDraft);
  let recurring = $state<RecurringItem[]>(recurringSuggestions());
  let quick = $state<QuickItem[]>([
    ...store.quickExpenses.map(existingQuickItem),
    ...quickSuggestions().filter(s => !store.quickExpenses.some(q => q.name.toLowerCase() === s.name.toLowerCase())),
  ]);
  let isStudent = $state(false);
  let izlyOn = $state(true);
  let izlyBalance = $state("");
  const izlyID = newID();

  const isOptional = $derived(step === "recurring" || step === "quick");
  const existingIzly = $derived(store.accounts.find(a => a.kind === "izly") ?? null);
  const izlyEnabled = $derived(isStudent && izlyOn && existingIzly === null);
  const izlyBalanceValid = $derived(isBlank(izlyBalance) || parseDecimal(izlyBalance) !== null);
  const canContinue = $derived.by(() => {
    switch (step) {
      case "account": return validated(draft) !== null && (!izlyEnabled || izlyBalanceValid);
      case "recurring": return recurring.every(r => !r.selected || recurringValid(r));
      case "quick": return quick.every(quickValid);
      default: return true;
    }
  });

  const otherAccounts = $derived(store.accounts.filter(a => a.id !== MAIN_ACCOUNT_ID && !a.isArchived));
  const selectedRecurring = $derived(recurring.filter(r => r.selected && recurringValid(r)));
  const selectedQuick = $derived.by(() => {
    const accountID = izlyEnabled ? izlyID : existingIzly?.id ?? null;
    return quick.flatMap(item => toQuickExpense(item.isCrous ? { ...item, accountID } : item, store) ?? []);
  });

  function go(delta: number) {
    const next = stepIndex + delta;
    if (next < 0 || next >= steps.length) return;
    goingForward = delta > 0;
    if (step === "student") syncCrous();
    stepIndex = next;
  }

  /// « Passer » : on ignore la sélection de l'étape.
  function skip() {
    if (step === "recurring") for (const r of recurring) r.selected = false;
    else if (step === "quick") for (const q of quick) if (!q.existing) q.selected = false;
    go(1);
  }

  /// Ajoute ou retire la suggestion « Repas Crous » selon la réponse.
  function syncCrous() {
    if (isStudent) {
      if (quick.some(q => q.isCrous)) return;
      const known = store.categories.some(c => c.id === "restaurants" && !c.isHidden && c.kind === "expense");
      quick.unshift(crousItem(known ? "restaurants" : "otherExpense"));
    } else {
      quick = quick.filter(q => !q.isCrous);
    }
  }

  /// Écrit tout dans le magasin, puis ferme l'assistant.
  function finish() {
    const account = validated(draft);
    if (!account) return;
    upsertAccount(store, account);
    if (isStudent) {
      prefs.studentProfile.value = true;
      if (izlyEnabled) {
        const cents = parseDecimal(izlyBalance);
        upsertAccount(store, makeIzly(store.accounts, currentTheme().categoryPalette.length,
                                      { id: izlyID, balanceCents: cents === null ? 0 : Math.round(cents * 100) }));
      }
    }
    for (const item of selectedRecurring) {
      const amount = itemAmount(item), day = itemDay(item);
      if (amount === null || day === null) continue;
      const known = store.categories.some(c => c.id === item.categoryID && !c.isHidden && c.kind === item.kind);
      upsertRecurring(store, {
        id: newID(), name: item.name.trim(), amountCents: amount, kind: item.kind,
        categoryID: known ? item.categoryID : store.fallbackCategory(item.kind).id,
        accountID: null, note: "", frequency: "monthly", startDate: nextDate(day), endDate: null, isActive: true, lastGeneratedDate: null,
      });
    }
    store.quickExpenses = selectedQuick;
    store.saveSettings();
    onfinish();
  }

  const summary = $derived([
    { icon: "star.fill", title: "Compte par défaut", value: draft.account.name },
    { icon: "building.columns.fill", title: "Autres comptes", value: count(otherAccounts.length + (izlyEnabled ? 1 : 0), "compte", "comptes") },
    { icon: "repeat", title: "Opérations récurrentes", value: count(selectedRecurring.length, "récurrente", "récurrentes") },
    { icon: "bolt.fill", title: "Ajouts rapides", value: count(selectedQuick.length, "ajout rapide", "ajouts rapides") },
  ]);
</script>

<div class="overlay" role="region" aria-label="Assistant de démarrage">
  <header>
    <span class="caption">{stepIndex + 1} / {steps.length}</span>
    <div class="bars">
      {#each steps as s, i (s)}<span class="bar" class:on={i <= stepIndex}></span>{/each}
    </div>
  </header>

  <div class="scroll">
    {#key step}
      <div class="content" in:fly={{ x: goingForward ? 60 : -60, duration: 300 }}>
        {#if step === "welcome"}
          <div class="welcome">
            <span class="logo"><Icon name="eurosign.circle.fill" size={64} color="var(--hero-text-primary)" strokeWidth={1.75} /></span>
            <h1 class="large-amount">Bienvenue dans Budget</h1>
            <p class="secondary lead">Suis tes dépenses, tes revenus et tes comptes au même endroit. Quelques questions pour tout préparer, ça prend une minute.</p>
            <div class="join">
              <button type="button" class="btn" onclick={() => (showSync = true)}>
                <Icon name="arrow.triangle.2.circlepath.icloud" size={15} /> J’utilise déjà Budget sur un autre appareil
              </button>
              <span class="caption tertiary">Choisis le dossier de synchronisation utilisé sur ton autre appareil.</span>
            </div>
          </div>
        {:else if step === "student"}
          <StudentStep bind:isStudent />
        {:else if step === "account"}
          <AccountStep {draft} {isStudent} showIzly={existingIzly === null} bind:izlyOn bind:izlyBalance />
        {:else if step === "recurring"}
          <RecurringStep items={recurring} />
        {:else if step === "quick"}
          <QuickStep items={quick} />
        {:else}
          <div class="col" style:gap="var(--padding)">
            <StepHeader title="Tout est prêt" subtitle="Voici ce qui va être configuré. Tu pourras tout modifier ensuite dans l’app." />
            <Card>
              {#each summary as row (row.title)}
                <div class="row">
                  <span class="chip-icon"><Icon name={row.icon} size={16} color="var(--accent)" /></span>
                  <span class="secondary">{row.title}</span>
                  <span class="spacer"></span>
                  <span class="amount truncate">{row.value}</span>
                </div>
              {/each}
            </Card>
          </div>
        {/if}
      </div>
    {/key}
  </div>

  <footer>
    {#if step !== "welcome"}<button type="button" class="link secondary" onclick={() => go(-1)}>Retour</button>{/if}
    <span class="spacer"></span>
    {#if isOptional}<button type="button" class="link secondary skip" onclick={skip}>Passer</button>{/if}
    <button type="button" class="cta" disabled={!canContinue} onclick={() => (step === "done" ? finish() : go(1))}>
      {step === "done" ? "Commencer" : "Continuer"}
    </button>
  </footer>
</div>

{#if showSync}
  <Sheet title="Synchronisation" onclose={() => (showSync = false)} width={600}>
    <SyncSettings />
    {#snippet footer()}
      <button type="button" class="btn" onclick={() => (showSync = false)}>Fermer</button>
      <button type="button" class="btn primary" onclick={() => { showSync = false; onfinish(); }}>Utiliser les données récupérées</button>
    {/snippet}
  </Sheet>
{/if}

<style>
  .overlay {
    position: fixed; inset: 0; z-index: 95; display: flex; flex-direction: column;
    background: linear-gradient(to bottom, var(--bg-top), var(--bg-bottom)), var(--background);
  }
  header {
    width: 100%; max-width: 720px; margin: 0 auto; padding: var(--padding) calc(var(--padding) * 2) 0;
    display: flex; align-items: center; gap: var(--spacing);
  }
  .bars { flex: 1; display: flex; gap: 4px; }
  .bar { flex: 1; height: 4px; border-radius: 2px; background: var(--surface-secondary); }
  .bar.on { background: var(--accent); }
  .scroll { flex: 1; overflow: auto; }
  .content { max-width: 720px; margin: 0 auto; padding: var(--padding) calc(var(--padding) * 2); }
  .welcome { display: flex; flex-direction: column; align-items: center; gap: calc(var(--padding) * 1.5); padding: calc(var(--padding) * 3) 0; text-align: center; }
  .welcome h1, .welcome p { margin: 0; }
  .lead { max-width: 440px; }
  .logo {
    width: 128px; height: 128px; display: inline-flex; align-items: center; justify-content: center;
    border-radius: calc(var(--radius) * 2); background: linear-gradient(135deg, var(--hero-start), var(--hero-end));
    box-shadow: var(--hero-shadow);
  }
  .join { display: flex; flex-direction: column; align-items: center; gap: 6px; max-width: 440px; margin-top: var(--spacing); }
  footer {
    width: 100%; max-width: 720px; margin: 0 auto; display: flex; align-items: center; gap: var(--spacing);
    padding: calc(var(--padding) * 1.5) calc(var(--padding) * 2);
  }
  .link { border: none; background: transparent; padding: 4px; }
  .skip { margin-right: var(--spacing); }
  .cta {
    border: none; border-radius: 999px; background: var(--accent); color: var(--on-accent);
    font-size: var(--title); font-weight: var(--title-weight); padding: var(--spacing) calc(var(--padding) * 1.5);
  }
  .cta:disabled { opacity: 0.4; }
  .chip-icon {
    width: 34px; height: 34px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center;
    background: color-mix(in srgb, var(--accent) calc(var(--badge-opacity) * 100%), transparent);
  }
</style>
