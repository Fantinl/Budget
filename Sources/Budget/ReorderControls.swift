import SwiftUI

/// Flèches ↑ ↓ pour réordonner une ligne (le glisser-déposer des listes est peu fiable sur Mac
/// quand la ligne est elle-même un bouton).
struct ReorderButtons: View {
    @Environment(\.theme) private var theme
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (ReorderMove) -> Void

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.up", label: "Monter", enabled: canMoveUp) { move(.up) }
            arrow("chevron.down", label: "Descendre", enabled: canMoveDown) { move(.down) }
        }
    }

    private func arrow(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(theme.captionFont)
                .foregroundStyle(enabled ? theme.textSecondary : theme.textTertiary.opacity(0.4))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Entrées de menu contextuel équivalentes.
struct ReorderMenuItems: View {
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (ReorderMove) -> Void

    var body: some View {
        Button("Monter", systemImage: "chevron.up") { move(.up) }.disabled(!canMoveUp)
        Button("Descendre", systemImage: "chevron.down") { move(.down) }.disabled(!canMoveDown)
        Button("Placer en premier", systemImage: "arrow.up.to.line") { move(.first) }.disabled(!canMoveUp)
        Button("Placer en dernier", systemImage: "arrow.down.to.line") { move(.last) }.disabled(!canMoveDown)
    }
}

enum ReorderMove {
    case up, down, first, last

    /// Destination au sens de `onMove` / `Array.move(fromOffsets:toOffset:)` pour l'élément d'indice `index`.
    func destination(from index: Int, count: Int) -> Int {
        switch self {
        case .up: max(0, index - 1)
        case .down: min(count, index + 2)
        case .first: 0
        case .last: count
        }
    }
}
