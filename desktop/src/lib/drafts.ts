// Opération en cours d'édition (struct Draft de ContentView.swift).
import type { Transaction } from "./model";

export interface Draft {
  transaction: Transaction;
  /// Nouvelle opération (pas encore enregistrée).
  isNew: boolean;
}
