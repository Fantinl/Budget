// Réordonnancement des listes des réglages (ReorderControls.swift).

// MARK: - Réordonnancement

export type ReorderMove = "up" | "down" | "first" | "last";

/// Destination au sens de `onMove` / `Array.move(fromOffsets:toOffset:)` pour l'élément d'indice `index`.
export function moveDestination(move: ReorderMove, index: number, count: number): number {
  switch (move) {
    case "up": return Math.max(0, index - 1);
    case "down": return Math.min(count, index + 2);
    case "first": return 0;
    case "last": return count;
  }
}
