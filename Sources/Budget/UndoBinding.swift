import SwiftUI

/// Branche le gestionnaire d'annulation de la fenêtre au store, pour que ⌘Z annule les modifications.
/// À poser sur la vue racine de chaque fenêtre (principale, réglages).
private struct UndoBinding: ViewModifier {
    @Environment(BudgetStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    #if os(macOS)
    @Environment(\.controlActiveState) private var activeState
    #endif

    func body(content: Content) -> some View {
        content
            .onAppear { store.undoManager = undoManager }
            #if os(macOS)
            // La fenêtre au premier plan reçoit les annulations.
            .onChange(of: activeState) { _, state in
                if state == .key { store.undoManager = undoManager }
            }
            #endif
    }
}

extension View {
    func bindsUndoToStore() -> some View { modifier(UndoBinding()) }
}
