// Touches : ⌘ sur Mac = Ctrl sur Windows (voir PORTAGE.md).

export const isMac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/i.test(navigator.platform ?? "");

/// « ⌘N » sur Mac, « Ctrl+N » ailleurs (infobulles).
export const shortcutLabel = (key: string) => (isMac ? `⌘${key}` : `Ctrl+${key}`);

/// ⌘ (Mac) ou Ctrl (Windows) enfoncé.
export const hasMod = (e: KeyboardEvent | MouseEvent) => e.metaKey || e.ctrlKey;

/// Un champ de texte a le focus.
export function isEditing(el: Element | null = document.activeElement): boolean {
  return el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement
    || (el instanceof HTMLElement && el.isContentEditable);
}

/// Une feuille modale (ou les réglages) est ouverte : les raccourcis de la page sont suspendus.
export const modalOpen = () => document.querySelector('[role="dialog"]') !== null;
