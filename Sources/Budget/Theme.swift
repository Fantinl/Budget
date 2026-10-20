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
    static let all: [Theme] = [.minimal, .vivid, .ocean, .forest, .sand, .contrast]

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
    // MARK: Palettes de catégories (séparées pour alléger la compilation)

    private static let oceanPalette: [Color] = [
        Color(hex: 0x2DB87A), Color(hex: 0x7A6A5A), Color(hex: 0x2F80ED), Color(hex: 0xF29B38),
        Color(hex: 0x8E6CF0), Color(hex: 0xE5586B), Color(hex: 0xE87BB0), Color(hex: 0x4558D6),
        Color(hex: 0x8A9BA8), Color(hex: 0x14A89A), Color(hex: 0x2BB3E6), Color(hex: 0x6FD0C5),
    ]
    private static let forestPalette: [Color] = [
        Color(hex: 0x5FA86A), Color(hex: 0xA0825A), Color(hex: 0x4A86B5), Color(hex: 0xE09A3E),
        Color(hex: 0x8C6BB5), Color(hex: 0xCB5A4C), Color(hex: 0xD9799B), Color(hex: 0x5D6FBF),
        Color(hex: 0x8E9A8A), Color(hex: 0x2F9E7E), Color(hex: 0x5BAFC4), Color(hex: 0xA6B84A),
    ]
    private static let sandPalette: [Color] = [
        Color(hex: 0x7E9A5B), Color(hex: 0xA67C52), Color(hex: 0x4F7FA8), Color(hex: 0xE0933C),
        Color(hex: 0x8A6BA8), Color(hex: 0xC8553D), Color(hex: 0xD97B9A), Color(hex: 0x5E6BB0),
        Color(hex: 0x9A8F82), Color(hex: 0x3E9A87), Color(hex: 0x5AA7C2), Color(hex: 0xB8B34A),
    ]
    private static let contrastPalette: [Color] = [
        Color(hex: 0x00A651), Color(hex: 0x8B5A2B), Color(hex: 0x0057E7), Color(hex: 0xFF8000),
        Color(hex: 0x8000FF), Color(hex: 0xE60026), Color(hex: 0xFF3399), Color(hex: 0x2B2BCC),
        Color(hex: 0x707070), Color(hex: 0x00A89D), Color(hex: 0x00AEEF), Color(hex: 0x99CC00),
    ]

    /// Style 3 — Océan : bleus et turquoises, fond bleuté, héros en dégradé bleu → turquoise.
    static let ocean = Theme(
        id: "ocean",
        name: "Océan",

        background: Color(light: Color(hex: 0xEEF6FA), dark: Color(hex: 0x0A1620)),
        surface: Color(light: .white, dark: Color(hex: 0x12212E)),
        surfaceSecondary: Color(light: Color(hex: 0xE1EEF5), dark: Color(hex: 0x1B3042)),
        separator: Color(light: Color(hex: 0xD3E4EE), dark: Color(hex: 0x244058)),

        textPrimary: Color(light: Color(hex: 0x0C2230), dark: Color(hex: 0xEAF5FA)),
        textSecondary: Color(light: Color(hex: 0x4B6678), dark: Color(hex: 0x9DB8C8)),
        textTertiary: Color(light: Color(hex: 0x82A0B2), dark: Color(hex: 0x5F7E91)),

        accent: Color(light: Color(hex: 0x0A7F8C), dark: Color(hex: 0x2CC4CF)),
        positive: Color(light: Color(hex: 0x0F9D6B), dark: Color(hex: 0x34D399)),
        negative: Color(light: Color(hex: 0xE04F5F), dark: Color(hex: 0xFF7385)),

        categoryPalette: oceanPalette,
        categoryFallback: Color(hex: 0x8A9BA8),

        fontDesign: .rounded,
        largeAmountFont: .system(size: 36, weight: .semibold, design: .rounded),
        amountFont: .system(.body, design: .rounded).weight(.semibold),
        titleFont: .system(.headline, design: .rounded),
        bodyFont: .system(.body, design: .rounded),
        captionFont: .system(.caption, design: .rounded),

        cornerRadius: 18,
        smallCornerRadius: 10,
        spacing: 12,
        padding: 16,
        iconSize: 36,

        backgroundTop: Color(light: Color(hex: 0xE8F4FA), dark: Color(hex: 0x0C1C2A)),
        backgroundBottom: Color(light: Color(hex: 0xF2FAF9), dark: Color(hex: 0x08131B)),

        cardShadowColor: Color(light: Color(hex: 0x0A5A7A).opacity(0.10), dark: Color.black.opacity(0.35)),
        cardShadowRadius: 10,
        cardShadowY: 4,
        cardBorder: Color(light: Color.white.opacity(0.9), dark: Color.white.opacity(0.05)),
        cardBorderWidth: 1,

        badgeFillOpacity: 0.18,

        heroGradientStart: Color(light: Color(hex: 0x1C6FD1), dark: Color(hex: 0x15509E)),
        heroGradientEnd: Color(light: Color(hex: 0x0E9A9A), dark: Color(hex: 0x0C7F85)),
        heroTextPrimary: .white,
        heroTextSecondary: Color.white.opacity(0.82),
        heroShadowColor: Color(light: Color(hex: 0x1C6FD1).opacity(0.30), dark: Color.black.opacity(0.45)),
        heroShadowRadius: 18,
        heroTintsBalance: false,
        onAccent: Color(light: .white, dark: Color(hex: 0x06222B)),
        warning: Color(hex: 0xE8A33D)
    )

    /// Style 4 — Forêt : verts sauge et mousse, bois clair, accent vert sapin.
    static let forest = Theme(
        id: "forest",
        name: "Forêt",

        background: Color(light: Color(hex: 0xF1F3EC), dark: Color(hex: 0x10150F)),
        surface: Color(light: Color(hex: 0xFAFBF6), dark: Color(hex: 0x1A211A)),
        surfaceSecondary: Color(light: Color(hex: 0xE5E9DC), dark: Color(hex: 0x252E24)),
        separator: Color(light: Color(hex: 0xD8DECD), dark: Color(hex: 0x303B2E)),

        textPrimary: Color(light: Color(hex: 0x1B2A1C), dark: Color(hex: 0xEDF2E6)),
        textSecondary: Color(light: Color(hex: 0x566652), dark: Color(hex: 0xA3B39D)),
        textTertiary: Color(light: Color(hex: 0x8A9885), dark: Color(hex: 0x68775F)),

        accent: Color(light: Color(hex: 0x2E6B4A), dark: Color(hex: 0x6FBF8E)),
        positive: Color(light: Color(hex: 0x2E8B57), dark: Color(hex: 0x5BCB8A)),
        negative: Color(light: Color(hex: 0xC8483E), dark: Color(hex: 0xF07A6E)),

        categoryPalette: forestPalette,
        categoryFallback: Color(hex: 0x8E9A8A),

        fontDesign: .rounded,
        largeAmountFont: .system(size: 34, weight: .semibold, design: .rounded),
        amountFont: .system(.body, design: .rounded).weight(.medium),
        titleFont: .system(.headline, design: .rounded),
        bodyFont: .system(.body, design: .rounded),
        captionFont: .system(.caption, design: .rounded),

        cornerRadius: 16,
        smallCornerRadius: 9,
        spacing: 12,
        padding: 16,
        iconSize: 34,

        backgroundTop: Color(light: Color(hex: 0xF1F3EC), dark: Color(hex: 0x10150F)),
        backgroundBottom: Color(light: Color(hex: 0xE9EEE2), dark: Color(hex: 0x0C100B)),

        cardShadowColor: Color(light: Color(hex: 0x2E4A33).opacity(0.08), dark: Color.black.opacity(0.30)),
        cardShadowRadius: 8,
        cardShadowY: 3,
        cardBorder: Color(light: Color(hex: 0xD8DECD).opacity(0.7), dark: Color.white.opacity(0.04)),
        cardBorderWidth: 1,

        badgeFillOpacity: 0.18,

        heroGradientStart: Color(light: Color(hex: 0x1F4D36), dark: Color(hex: 0x17402D)),
        heroGradientEnd: Color(light: Color(hex: 0x3C7A55), dark: Color(hex: 0x2F6446)),
        heroTextPrimary: .white,
        heroTextSecondary: Color.white.opacity(0.80),
        heroShadowColor: Color(light: Color(hex: 0x1F4D36).opacity(0.28), dark: Color.black.opacity(0.45)),
        heroShadowRadius: 16,
        heroTintsBalance: false,
        onAccent: Color(light: .white, dark: Color(hex: 0x0E2417)),
        warning: Color(hex: 0xD9962B)
    )

    /// Style 5 — Sable : terre, terracotta et crème, ambiance papier, titres et montants en serif.
    static let sand = Theme(
        id: "sand",
        name: "Sable",

        background: Color(light: Color(hex: 0xF6EFE4), dark: Color(hex: 0x1A1511)),
        surface: Color(light: Color(hex: 0xFFFAF2), dark: Color(hex: 0x241D17)),
        surfaceSecondary: Color(light: Color(hex: 0xEDE3D3), dark: Color(hex: 0x30271F)),
        separator: Color(light: Color(hex: 0xE2D6C2), dark: Color(hex: 0x3D3228)),

        textPrimary: Color(light: Color(hex: 0x2E2118), dark: Color(hex: 0xF4EBDD)),
        textSecondary: Color(light: Color(hex: 0x6B5846), dark: Color(hex: 0xBBA98F)),
        textTertiary: Color(light: Color(hex: 0x9C8A74), dark: Color(hex: 0x85755F)),

        accent: Color(light: Color(hex: 0xB5522F), dark: Color(hex: 0xE2845E)),
        positive: Color(light: Color(hex: 0x4F8A4B), dark: Color(hex: 0x8CC27F)),
        negative: Color(light: Color(hex: 0xB83A3A), dark: Color(hex: 0xF08080)),

        categoryPalette: sandPalette,
        categoryFallback: Color(hex: 0x9A8F82),

        fontDesign: .serif,
        largeAmountFont: .system(size: 36, weight: .semibold, design: .serif),
        amountFont: .system(.body, design: .serif).weight(.semibold),
        titleFont: .system(.headline, design: .serif),
        bodyFont: .system(.body, design: .rounded),
        captionFont: .system(.caption, design: .rounded),

        cornerRadius: 14,
        smallCornerRadius: 8,
        spacing: 12,
        padding: 16,
        iconSize: 34,

        backgroundTop: Color(light: Color(hex: 0xF8F1E6), dark: Color(hex: 0x1C1712)),
        backgroundBottom: Color(light: Color(hex: 0xF2E8D8), dark: Color(hex: 0x16120E)),

        cardShadowColor: Color(light: Color(hex: 0x7A5230).opacity(0.10), dark: Color.black.opacity(0.30)),
        cardShadowRadius: 8,
        cardShadowY: 3,
        cardBorder: Color(light: Color(hex: 0xE2D6C2), dark: Color.white.opacity(0.05)),
        cardBorderWidth: 1,

        badgeFillOpacity: 0.20,

        heroGradientStart: Color(light: Color(hex: 0xA84A28), dark: Color(hex: 0x8F3E20)),
        heroGradientEnd: Color(light: Color(hex: 0xB86A35), dark: Color(hex: 0xA55A2C)),
        heroTextPrimary: .white,
        heroTextSecondary: Color.white.opacity(0.85),
        heroShadowColor: Color(light: Color(hex: 0xA84A28).opacity(0.28), dark: Color.black.opacity(0.45)),
        heroShadowRadius: 16,
        heroTintsBalance: false,
        onAccent: Color(light: .white, dark: Color(hex: 0x2A140A)),
        warning: Color(hex: 0xD99A2B)
    )

    /// Style 6 — Contraste : noir et blanc nets, accent orange / jaune vif, sans ombres, bordures marquées.
    static let contrast = Theme(
        id: "contrast",
        name: "Contraste",

        background: Color(light: .white, dark: .black),
        surface: Color(light: .white, dark: Color(hex: 0x0D0D0D)),
        surfaceSecondary: Color(light: Color(hex: 0xEDEDED), dark: Color(hex: 0x262626)),
        separator: Color(light: .black, dark: .white),

        textPrimary: Color(light: .black, dark: .white),
        textSecondary: Color(light: Color(hex: 0x333333), dark: Color(hex: 0xD9D9D9)),
        textTertiary: Color(light: Color(hex: 0x595959), dark: Color(hex: 0xB3B3B3)),

        accent: Color(light: Color(hex: 0xC2410C), dark: Color(hex: 0xFFD60A)),
        positive: Color(light: Color(hex: 0x006B2E), dark: Color(hex: 0x4DFF88)),
        negative: Color(light: Color(hex: 0xB00020), dark: Color(hex: 0xFF6B6B)),

        categoryPalette: contrastPalette,
        categoryFallback: Color(hex: 0x707070),

        fontDesign: .default,
        largeAmountFont: .system(size: 38, weight: .heavy, design: .default),
        amountFont: .system(.body, design: .default).weight(.bold),
        titleFont: .system(.headline, design: .default).weight(.heavy),
        bodyFont: .system(.body, design: .default),
        captionFont: .system(.caption, design: .default).weight(.semibold),

        cornerRadius: 10,
        smallCornerRadius: 6,
        spacing: 12,
        padding: 16,
        iconSize: 36,

        backgroundTop: Color(light: .white, dark: .black),
        backgroundBottom: Color(light: .white, dark: .black),

        cardShadowColor: .clear,
        cardShadowRadius: 0,
        cardShadowY: 0,
        cardBorder: Color(light: .black, dark: .white),
        cardBorderWidth: 1.5,

        badgeFillOpacity: 0.30,

        heroGradientStart: Color(light: .black, dark: Color(hex: 0xFFD60A)),
        heroGradientEnd: Color(light: Color(hex: 0x222222), dark: Color(hex: 0xFFB000)),
        heroTextPrimary: Color(light: .white, dark: .black),
        heroTextSecondary: Color(light: Color.white.opacity(0.88), dark: Color.black.opacity(0.80)),
        heroShadowColor: .clear,
        heroShadowRadius: 0,
        heroTintsBalance: false,
        onAccent: Color(light: .white, dark: .black),
        warning: Color(light: Color(hex: 0xB85C00), dark: Color(hex: 0xFFB000))
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
