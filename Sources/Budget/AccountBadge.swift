import SwiftUI

extension Theme {
    /// Couleur d'un compte dans la palette du thème.
    func color(for account: Account) -> Color {
        categoryPalette.indices.contains(account.colorIndex) ? categoryPalette[account.colorIndex] : categoryFallback
    }
}

/// Pastille ronde d'un compte : icône du type sur fond couleur à faible opacité.
struct AccountBadge: View {
    @Environment(\.theme) private var theme
    let account: Account
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: account.kind.icon)
            .font(.system(size: size * 0.42, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.color(for: account))
            .frame(width: size, height: size)
            .background(theme.color(for: account).opacity(theme.badgeFillOpacity), in: .circle)
    }
}
