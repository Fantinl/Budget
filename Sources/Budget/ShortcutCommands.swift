import SwiftUI

/// Actions exposées par l'écran Opérations à la barre de menus (nil = indisponible, item grisé).
struct OperationActions {
    var newOperation: () -> Void
    var expressEntry: () -> Void
    var search: (() -> Void)?
    var previousMonth: (() -> Void)?
    var nextMonth: (() -> Void)?
}

struct OperationActionsKey: FocusedValueKey {
    typealias Value = OperationActions
}

extension FocusedValues {
    var operationActions: OperationActions? {
        get { self[OperationActionsKey.self] }
        set { self[OperationActionsKey.self] = newValue }
    }
}

extension Notification.Name {
    /// Demande de placer le curseur dans la saisie express (⌘E).
    static let focusExpressEntry = Notification.Name("budget.focusExpressEntry")
}

/// Menu « Opérations » de la barre de menus.
struct OperationsCommands: Commands {
    @FocusedValue(\.operationActions) private var actions

    var body: some Commands {
        CommandMenu("Opérations") {
            Button("Nouvelle opération") { actions?.newOperation() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(actions == nil)
            Button("Saisie express") { actions?.expressEntry() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(actions == nil)
            Button("Rechercher") { actions?.search?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions?.search == nil)
            Divider()
            Button("Mois précédent") { actions?.previousMonth?() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(actions?.previousMonth == nil)
            Button("Mois suivant") { actions?.nextMonth?() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(actions?.nextMonth == nil)
        }
    }
}

#if os(macOS)
/// Entrée du menu Aide qui ouvre la fenêtre des raccourcis (⌘/).
struct ShortcutsHelpCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Raccourcis clavier") { openWindow(id: "shortcuts") }
            .keyboardShortcut("/", modifiers: .command)
    }
}
#endif
