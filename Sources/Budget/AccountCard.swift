import SwiftUI

/// Libellé « Banque · Type » d'un compte.
func accountSubtitle(_ account: Account) -> String {
    account.bank.flatMap { $0.isEmpty ? nil : $0 }.map { "\($0) · \(account.kind.label)" } ?? account.kind.label
}

/// Pourcentage lisible en français (« 3,2 % »).
func percentText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1))) + " %"
}

/// Contenu d'une carte de compte façon appli bancaire : en-tête, solde, puis détails selon le type.
/// `large` = version de l'en-tête de la page de détail.
struct AccountCardContent: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    let account: Account
    var large = false

    var body: some View {
        let value = store.value(of: account)
        VStack(alignment: .leading, spacing: theme.spacing) {
            HStack(spacing: theme.spacing) {
                AccountBadge(account: account, size: large ? 48 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(large ? theme.largeAmountFont : theme.titleFont)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(accountSubtitle(account))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(value.euros)
                .font(theme.largeAmountFont)
                .monospacedDigit()
                .foregroundStyle(value < 0 ? theme.negative : theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            details
        }
    }

    @ViewBuilder private var details: some View {
        let tint = theme.color(for: account)
        if let ceiling = account.kind.ceiling {
            let amount = store.balance(of: account)
            let progress = ceiling > 0 ? min(max(Double(truncating: (amount / ceiling) as NSNumber), 0), 1) : 0
            VStack(alignment: .leading, spacing: 4) {
                ProgressBar(progress: progress, tint: tint)
                Text("\(amount.euros) / \(ceiling.euros)")
                    .font(theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        if account.kind.hasMarketValue {
            investmentDetails
        }
        if let rate = account.interestRate {
            Label("Taux \(rate.formatted(.number.precision(.fractionLength(0...2)))) %", systemImage: "percent")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder private var investmentDetails: some View {
        let paid = store.balance(of: account)
        if let gain = store.gain(of: account) {
            let pct = paid != 0 ? Double(truncating: (gain / paid * 100) as NSNumber) : nil
            VStack(alignment: .leading, spacing: 2) {
                Text("Versements : \(paid.euros)")
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 4) {
                    Image(systemName: gain >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text((gain > 0 ? "+" : "") + gain.euros + (pct.map { " (\(gain > 0 ? "+" : "")\(percentText($0)))" } ?? ""))
                        .monospacedDigit()
                }
                .foregroundStyle(gain >= 0 ? theme.positive : theme.negative)
            }
            .font(theme.captionFont)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Versements : \(paid.euros)")
                Text("Valorisation non renseignée")
                    .foregroundStyle(theme.textTertiary)
            }
            .font(theme.captionFont)
            .foregroundStyle(theme.textSecondary)
        }
    }
}

/// Fine barre de progression.
struct ProgressBar: View {
    @Environment(\.theme) private var theme
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.surfaceSecondary)
                Capsule().fill(tint).frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

/// Fond d'une carte de compte : surface, avec dégradé léger de la couleur du compte.
struct AccountCardBackground: ViewModifier {
    @Environment(\.theme) private var theme
    let account: Account
    var archived = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
        let tint = theme.color(for: account)
        content
            .padding(theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(theme.surface)
                    shape.fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.04)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(alignment: .top) {
                // Bandeau de couleur en haut de la carte
                Rectangle().fill(tint).frame(height: 4)
                    .clipShape(.rect(topLeadingRadius: theme.cornerRadius, topTrailingRadius: theme.cornerRadius))
            }
            .overlay(shape.strokeBorder(theme.cardBorder, lineWidth: theme.cardBorderWidth))
            .shadow(color: theme.cardShadowColor, radius: theme.cardShadowRadius, y: theme.cardShadowY)
            .opacity(archived ? 0.55 : 1)
    }
}

extension View {
    func accountCardBackground(_ account: Account, archived: Bool = false) -> some View {
        modifier(AccountCardBackground(account: account, archived: archived))
    }
}
