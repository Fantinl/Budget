// Tags : étiquettes libres posées sur les opérations, en plus de la catégorie. Port de BudgetStore+Tags.swift.
// (L'écran de réglages des tags importe ces fonctions.)

import { type Tag, type Transaction, newID } from "../model";
import { categoryColor } from "../theme.svelte";
import type { BudgetStore } from "../store.svelte";

export const tagByID = (s: BudgetStore, id: string): Tag | undefined => s.tags.find(t => t.id === id);

/// Tags d'une opération, dans l'ordre de `tags` (les identifiants inconnus sont ignorés).
export function tagsOf(s: BudgetStore, t: Transaction): Tag[] {
  const ids = t.tagIDs;
  if (!ids || ids.length === 0) return [];
  return s.tags.filter(tag => ids.includes(tag.id));
}

/// Nombre d'opérations portant ce tag.
export function tagUsageCount(s: BudgetStore, tag: Tag): number {
  let n = 0;
  for (const t of s.transactions) if ((t.tagIDs ?? []).includes(tag.id)) n++;
  return n;
}

export function upsertTag(s: BudgetStore, tag: Tag) {
  s.registerUndo("Modifier le tag");
  const index = s.tags.findIndex(t => t.id === tag.id);
  s.tags = index >= 0 ? s.tags.with(index, tag) : [...s.tags, tag];
  s.saveSettings();
}

/// Supprime le tag et le retire des opérations (qui sont conservées).
export function deleteTag(s: BudgetStore, tag: Tag) {
  s.registerUndo("Supprimer le tag");
  let changed = false;
  s.transactions = s.transactions.map(t => {
    if (!t.tagIDs || !t.tagIDs.includes(tag.id)) return t;
    changed = true;
    const ids = t.tagIDs.filter(id => id !== tag.id);
    return { ...t, tagIDs: ids.length === 0 ? null : ids };
  });
  if (changed) s.saveTransactions();
  s.tags = s.tags.filter(t => t.id !== tag.id);
  s.saveSettings();
}

/// Équivalent de `Array.move(fromOffsets:toOffset:)` de SwiftUI.
export function moveTags(s: BudgetStore, from: number[], to: number) {
  s.registerUndo("Réordonner les tags");
  const moving = [...from].sort((a, b) => a - b).map(i => s.tags[i]).filter(Boolean);
  const before = from.filter(i => i < to).length;
  const rest = s.tags.filter((_, i) => !from.includes(i));
  rest.splice(to - before, 0, ...moving);
  s.tags = rest;
  s.saveSettings();
}

/// Nom sans espaces autour ni « # » en tête, sans casse ni accents : sert à repérer les doublons.
export function tagKey(name: string): string {
  const clean = name.trim().replace(/^#+/, "");
  return clean.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
}

/// Crée un tag, sauf si un tag du même nom existe (casse et accents ignorés) : il est alors renvoyé.
export function addTag(s: BudgetStore, name: string): Tag {
  const key = tagKey(name);
  const existing = s.tags.find(t => tagKey(t.name) === key);
  if (existing) return existing;
  const tag: Tag = { id: newID(), name: name.trim().replace(/^#+/, ""), colorIndex: s.tags.length };
  upsertTag(s, tag);
  return tag;
}

/// Remplace les tags de plusieurs opérations (null si la liste est vide).
export function setTags(s: BudgetStore, ids: string[], transactionIDs: Set<string>) {
  s.registerUndo("Modifier les tags");
  s.transactions = s.transactions.map(t => (transactionIDs.has(t.id) ? { ...t, tagIDs: ids.length === 0 ? null : [...ids] } : t));
  s.saveTransactions();
}

/// Couleur CSS d'un tag.
export const tagColor = (tag: Tag) => categoryColor(tag.colorIndex);
