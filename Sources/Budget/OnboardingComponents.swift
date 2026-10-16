import SwiftUI

// Briques communes de l'assistant de démarrage.

/// Pastille sélectionnable (capsule), même style que dans l'éditeur de compte.
struct OnboardingChip: View {
    @Environment(\.theme) private var theme
    let title: String
    var icon: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title).lineLimit(1)
            }
            .font(theme.captionFont)
            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
            .padding(.horizontal, theme.spacing)
            .padding(.vertical, 7)
            .background(selected ? theme.accent.opacity(0.15) : theme.surfaceSecondary, in: .capsule)
            .overlay(Capsule().stroke(selected ? theme.accent : .clear, lineWidth: 1.5))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Titre et sous-titre d'une étape.
struct OnboardingStepHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(theme.largeAmountFont).foregroundStyle(theme.textPrimary)
            Text(subtitle).font(theme.bodyFont).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Case ronde cochable d'une ligne de suggestion.
struct OnboardingCheck: View {
    @Environment(\.theme) private var theme
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(theme.titleFont)
                .foregroundStyle(isOn ? theme.accent : theme.textTertiary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Champ de montant (ou de nombre) aligné à droite, avec unité.
struct OnboardingNumberField: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var text: String
    var unit: String
    var width: CGFloat = 72

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(theme.textPrimary)
                #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
                #endif
                .frame(width: width)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: theme.smallCornerRadius, style: .continuous))
            Text(unit).foregroundStyle(theme.textSecondary)
        }
        .font(theme.bodyFont)
    }
}

enum OnboardingFormat {
    /// Montant éditable (« 2,5 »).
    static func text(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// Montant strictement positif, nil sinon.
    static func positive(_ text: String) -> Decimal? {
        guard let value = AccountDraft.parse(text), value > 0 else { return nil }
        return value
    }
}

/// Texte pluriel simple : « 2 comptes ».
func onboardingCount(_ n: Int, _ singular: String, _ plural: String) -> String {
    "\(n) \(n > 1 ? plural : singular)"
}
