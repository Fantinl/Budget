import SwiftUI

/// Ligne de la barre latérale : tuile colorée, libellé et info discrète.
struct SidebarRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let symbol: String
    let tint: Color
    let info: String?

    var body: some View {
        HStack(spacing: theme.spacing) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 26, height: 26)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: theme.smallCornerRadius, style: .continuous))
            Text(title)
                .font(theme.bodyFont)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let info {
                Text(info)
                    .font(theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.vertical, 3)
        .frame(minHeight: 34)
    }
}

/// En-tête : logo + nom de l'app, puis mini-résumé du patrimoine et du mois.
struct SidebarSummary: View {
    @Environment(\.theme) private var theme
    // nil = chiffre masqué (réglages → Apparence → Barre latérale)
    let wealth: String?
    let spent: String?
    let income: String?
    let balance: String?
    let balanceIsNegative: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            HStack(spacing: theme.spacing) {
                Image(systemName: "eurosign")
                    .font(.system(size: 16, weight: .bold, design: theme.fontDesign))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        LinearGradient(colors: [theme.heroGradientStart, theme.heroGradientEnd],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: theme.smallCornerRadius + 2, style: .continuous))
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.smallCornerRadius + 2, style: .continuous))
                Text("Budget")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
            }

            if wealth != nil || spent != nil || income != nil || balance != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let wealth { line("Patrimoine", wealth, theme.textPrimary) }
                    if let spent { line("Dépensé ce mois-ci", spent, theme.textSecondary) }
                    if let income { line("Revenus du mois", income, theme.positive) }
                    if let balance { line("Solde du mois", balance, balanceIsNegative ? theme.negative : theme.positive) }
                }
            }
        }
        .textCase(nil)
        .padding(.top, theme.spacing)
        .padding(.horizontal, 4)
    }

    private func line(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(theme.captionFont)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(theme.captionFont.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
