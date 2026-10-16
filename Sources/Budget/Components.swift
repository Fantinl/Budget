import SwiftUI

/// Carte arrondie sur fond `surface` (ombre et bordure selon le thème), sans marge extérieure.
struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var padded = true
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        content
            .padding(padded ? theme.padding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: shape)
            .overlay(shape.strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth))
            .shadow(color: theme.cardShadowColor, radius: theme.cardShadowRadius, y: theme.cardShadowY)
    }
}

/// Carte mise en avant (ex. solde du mois) : dégradé du thème. Les textes à l'intérieur
/// doivent utiliser `theme.heroTextPrimary` / `theme.heroTextSecondary`.
struct HeroCard<Content: View>: View {
    @Environment(\.theme) private var theme
    var padded = true
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        content
            .padding(padded ? theme.padding : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [theme.heroGradientStart, theme.heroGradientEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: shape
            )
            .overlay(shape.strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth))
            .shadow(color: theme.heroShadowColor, radius: theme.heroShadowRadius, y: theme.cardShadowY)
    }
}

/// Pastille ronde de catégorie : fond à faible opacité, icône en couleur pleine.
struct CategoryBadge: View {
    @Environment(\.theme) private var theme
    let category: Category
    var size: CGFloat?

    var body: some View {
        let diameter = size ?? theme.iconSize
        Image(systemName: category.icon)
            .font(.system(size: diameter * 0.42, weight: .medium, design: theme.fontDesign))
            .foregroundStyle(theme.color(for: category))
            .frame(width: diameter, height: diameter)
            .background(theme.color(for: category).opacity(theme.badgeFillOpacity), in: .circle)
    }
}

/// Fond d'écran du thème (uni ou dégradé), à utiliser à la place de `.background(theme.background)`.
private struct ScreenBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.background(
            LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
