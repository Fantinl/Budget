import SwiftUI

// MARK: - Thème de l'app
//
// C'est la « feuille de style » de l'app : toutes les couleurs, polices, espacements et
// arrondis viennent d'ici. Pour essayer un autre style, on crée un nouveau `Theme`
// (copier `minimal` et changer les valeurs) et on l'ajoute à `Theme.all` : il devient
// sélectionnable dans les réglages.
// Les vues ne doivent jamais coder une couleur ou une taille en dur : elles lisent
// `@Environment(\.theme)`.

struct Theme: Identifiable {
    var id: String               // clé enregistrée dans les préférences
    var name: String             // nom affiché dans les réglages

    // Couleurs de fond
    var background: Color        // fond de l'écran
    var surface: Color           // cartes, lignes, blocs
    var surfaceSecondary: Color  // éléments en retrait (champs, pistes de graphiques)
    var separator: Color

    // Texte
    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color

    // Accents
    var accent: Color            // boutons, sélection
    var positive: Color          // revenus, solde positif
    var negative: Color          // solde négatif, suppression

    // Couleurs des catégories : chaque catégorie choisit un index dans cette palette.
    var categoryPalette: [Color]
    var categoryFallback: Color  // catégorie supprimée

    // Typographie
    var fontDesign: Font.Design
    var largeAmountFont: Font    // grand montant (solde du mois…)
    var amountFont: Font         // montant dans une ligne
    var titleFont: Font          // titre de section / carte
    var bodyFont: Font
    var captionFont: Font        // libellés, légendes

    // Formes et espacements
    var cornerRadius: CGFloat    // cartes
    var smallCornerRadius: CGFloat // pastilles, barres
    var spacing: CGFloat         // espace standard entre éléments
    var padding: CGFloat         // marge intérieure des cartes
    var iconSize: CGFloat        // diamètre de la pastille de catégorie

    // Fond d'écran (dégradé vertical ; identiques = fond uni)
    var backgroundTop: Color
    var backgroundBottom: Color

    // Cartes : ombre et bordure
    var cardShadowColor: Color
    var cardShadowRadius: CGFloat
    var cardShadowY: CGFloat
    var cardBorder: Color
    var cardBorderWidth: CGFloat

    // Pastille de catégorie
    var badgeFillOpacity: Double

    // Carte mise en avant (solde du mois…) : dégradé diagonal + textes associés
    var heroGradientStart: Color
    var heroGradientEnd: Color
    var heroTextPrimary: Color
    var heroTextSecondary: Color
    var heroShadowColor: Color
    var heroShadowRadius: CGFloat
    /// Solde de la carte héros en vert/rouge (sinon en `heroTextPrimary`, pour rester lisible sur un dégradé).
    var heroTintsBalance = true
    /// Texte et icônes posés sur la couleur d'accent (bouton d'ajout…).
    var onAccent: Color = .white
    /// Alerte modérée (budget entre 80 et 100 %…).
    var warning: Color = Color(hex: 0xE8A33D)

    func color(for category: Category) -> Color {
        categoryPalette.indices.contains(category.colorIndex) ? categoryPalette[category.colorIndex] : categoryFallback
    }
}

extension Theme {
    /// Thèmes proposés dans les réglages.
    static let all: [Theme] = [.minimal, .vivid]

    /// Thème par défaut.
    static let current: Theme = .minimal

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? current
    }

    /// Style 1 — Minimal : fonds neutres, une seule couleur d'accent, palette de catégories douce.
    static let minimal = Theme(
        id: "minimal",
        name: "Minimal",

        background: Color(light: .init(white: 0.97), dark: .init(white: 0.07)),
        surface: Color(light: .white, dark: .init(white: 0.12)),
        surfaceSecondary: Color(light: .init(white: 0.94), dark: .init(white: 0.17)),
        separator: Color(light: .init(white: 0.90), dark: .init(white: 0.20)),

        textPrimary: Color(light: .init(white: 0.10), dark: .init(white: 0.95)),
        textSecondary: Color(light: .init(white: 0.45), dark: .init(white: 0.62)),
        textTertiary: Color(light: .init(white: 0.65), dark: .init(white: 0.42)),

        accent: Color(hex: 0x2F6BFF),
        positive: Color(hex: 0x1E9E6A),
        negative: Color(hex: 0xE5484D),

        categoryPalette: [
            Color(hex: 0x5FB58A), Color(hex: 0xB59A7A), Color(hex: 0x5B8DEF), Color(hex: 0xF0A04B),
            Color(hex: 0x9B7FE6), Color(hex: 0xE6787A), Color(hex: 0xE58BB8), Color(hex: 0x6C7AE0),
            Color(hex: 0x9AA0A6), Color(hex: 0x3FB8A0), Color(hex: 0x4FB3D9), Color(hex: 0x7CC4C0),
        ],
        categoryFallback: Color(hex: 0x9AA0A6),

        fontDesign: .rounded,
        largeAmountFont: .system(size: 34, weight: .semibold, design: .rounded),
        amountFont: .system(.body, design: .rounded).weight(.medium),
        titleFont: .system(.headline, design: .rounded),
        bodyFont: .system(.body, design: .rounded),
        captionFont: .system(.caption, design: .rounded),

        cornerRadius: 16,
        smallCornerRadius: 8,
        spacing: 12,
        padding: 16,
        iconSize: 34,

        backgroundTop: Color(light: .init(white: 0.97), dark: .init(white: 0.07)),
        backgroundBottom: Color(light: .init(white: 0.97), dark: .init(white: 0.07)),

        cardShadowColor: .clear,
        cardShadowRadius: 0,
        cardShadowY: 0,
        cardBorder: .clear,
        cardBorderWidth: 0,

        badgeFillOpacity: 0.15,

        heroGradientStart: Color(light: .white, dark: .init(white: 0.12)),
        heroGradientEnd: Color(light: .white, dark: .init(white: 0.12)),
        heroTextPrimary: Color(light: .init(white: 0.10), dark: .init(white: 0.95)),
        heroTextSecondary: Color(light: .init(white: 0.45), dark: .init(white: 0.62)),
        heroShadowColor: .clear,
        heroShadowRadius: 0
    )

    /// Style 2 — Vivant : fond teinté en dégradé, accent violet affirmé, catégories saturées,
    /// montants en gras, arrondis généreux, ombres douces, carte héros en dégradé.
    static let vivid = Theme(
        id: "vivid",
        name: "Vivant",

        background: Color(light: Color(hex: 0xF5F2FF), dark: Color(hex: 0x120F1C)),
        surface: Color(light: .white, dark: Color(hex: 0x1D1A2A)),
        surfaceSecondary: Color(light: Color(hex: 0xEDE9FB), dark: Color(hex: 0x2A2640)),
        separator: Color(light: Color(hex: 0xE3DEF5), dark: Color(hex: 0x332F4A)),

        textPrimary: Color(light: Color(hex: 0x1A1530), dark: Color(hex: 0xF4F1FF)),
        textSecondary: Color(light: Color(hex: 0x5E5878), dark: Color(hex: 0xA9A3C4)),
        textTertiary: Color(light: Color(hex: 0x948EAD), dark: Color(hex: 0x6F6A8A)),

        accent: Color(light: Color(hex: 0x6C47FF), dark: Color(hex: 0x8F77FF)),
        positive: Color(light: Color(hex: 0x0FA968), dark: Color(hex: 0x2FD68C)),
        negative: Color(light: Color(hex: 0xF03E5A), dark: Color(hex: 0xFF6B80)),

        categoryPalette: [
            Color(hex: 0x22C07A), Color(hex: 0xC9894A), Color(hex: 0x2F7BFF), Color(hex: 0xFF8A1F),
            Color(hex: 0x8E5CF7), Color(hex: 0xFF4D5E), Color(hex: 0xF04FA0), Color(hex: 0x4B5CF0),
            Color(hex: 0x7C8798), Color(hex: 0x12B5A0), Color(hex: 0x1AA7E8), Color(hex: 0x36C9B8),
        ],
        categoryFallback: Color(hex: 0x7C8798),

        fontDesign: .rounded,
        largeAmountFont: .system(size: 38, weight: .bold, design: .rounded),
        amountFont: .system(.body, design: .rounded).weight(.bold),
        titleFont: .system(.headline, design: .rounded).weight(.bold),
        bodyFont: .system(.body, design: .rounded),
        captionFont: .system(.caption, design: .rounded).weight(.medium),

        cornerRadius: 22,
        smallCornerRadius: 12,
        spacing: 14,
        padding: 18,
        iconSize: 38,

        backgroundTop: Color(light: Color(hex: 0xF3EEFF), dark: Color(hex: 0x1A1430)),
        backgroundBottom: Color(light: Color(hex: 0xFFF3EC), dark: Color(hex: 0x0F0D18)),

        cardShadowColor: Color(light: Color(hex: 0x4B2FB5).opacity(0.12), dark: Color.black.opacity(0.35)),
        cardShadowRadius: 14,
        cardShadowY: 5,
        cardBorder: Color(light: Color.white.opacity(0.8), dark: Color.white.opacity(0.06)),
        cardBorderWidth: 1,

        badgeFillOpacity: 0.20,

        heroGradientStart: Color(light: Color(hex: 0x6C47FF), dark: Color(hex: 0x5B3BE0)),
        heroGradientEnd: Color(light: Color(hex: 0xC04DFF), dark: Color(hex: 0xA03CD8)),
        heroTextPrimary: .white,
        heroTextSecondary: Color.white.opacity(0.78),
        heroShadowColor: Color(light: Color(hex: 0x6C47FF).opacity(0.35), dark: Color.black.opacity(0.45)),
        heroShadowRadius: 20,
        heroTintsBalance: false
    )
}

// MARK: - Accès via l'environnement

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .current
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Aides couleur

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Couleur qui s'adapte automatiquement au mode clair / sombre.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }
}

// MARK: - Mode clair / sombre

/// Choix de l'utilisateur dans les réglages ; « Automatique » suit le réglage du Mac / de l'iPhone.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var label: String {
        switch self {
        case .system: "Automatique"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    #if os(macOS)
    /// Appliqué à toute l'app (fenêtre principale et réglages). `nil` = suivre le système.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    #endif
}

// MARK: - Chiffres de la barre latérale

/// Clés des préférences « chiffres dans la barre latérale » (réglages → Apparence).
enum SidebarFigures {
    static let enabled = "sidebarFigures"          // interrupteur général
    static let wealth = "sidebarFigures.wealth"    // patrimoine
    static let spent = "sidebarFigures.spent"      // dépensé ce mois-ci
    static let income = "sidebarFigures.income"    // revenus du mois
    static let balance = "sidebarFigures.balance"  // solde du mois
    static let monthCount = "sidebarFigures.monthCount"      // nb d'opérations du mois, à côté d'« Opérations »
    static let accountCount = "sidebarFigures.accountCount"  // nb de comptes, à côté de « Comptes »
}
