import SwiftUI

/// Carte « Prévision » détaillée (Statistiques, mois en cours).
struct ForecastCard: View {
    @Environment(\.theme) private var theme
    @Environment(BudgetStore.self) private var store

    private var locale: Locale { Locale(identifier: "fr_FR") }

    var body: some View {
        let forecast = store.monthForecast()
        Card {
            VStack(alignment: .leading, spacing: theme.spacing) {
                Text("Prévision")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.textPrimary)
                line("Solde actuel du mois", forecast.current)
                if forecast.upcoming.isEmpty {
                    Text("Aucune opération récurrente à venir ce mois-ci.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    line("+ Récurrentes à venir", forecast.upcomingTotal)
                    ForEach(forecast.upcoming) { item in
                        HStack {
                            Text("\(item.date.formatted(Date.FormatStyle().day().month(.abbreviated).locale(locale))) · \(item.name)")
                                .lineLimit(1)
                            Spacer()
                            Text(item.amount.euros).monospacedDigit()
                        }
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.leading, theme.spacing)
                    }
                }
                if let estimate = forecast.estimatedSpending {
                    line("+ Dépenses courantes estimées", -estimate)
                } else {
                    Text("Pas assez d'historique pour estimer les dépenses courantes.")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textTertiary)
                }
                Divider().overlay(theme.separator)
                HStack {
                    Text("= Fin de mois prévue")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(forecast.projected.euros)
                        .font(theme.amountFont)
                        .foregroundStyle(forecast.projected >= 0 ? theme.positive : theme.negative)
                }
                Text("Prévu = revenus − dépenses du mois à ce jour, plus les opérations récurrentes à venir, moins une estimation des dépenses courantes (moyenne journalière hors récurrentes des 3 mois précédents × jours restants). Les virements sont ignorés.")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private func line(_ title: String, _ value: Decimal) -> some View {
        HStack {
            Text(title)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Text(value.euros)
                .font(theme.amountFont)
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)
        }
    }
}
