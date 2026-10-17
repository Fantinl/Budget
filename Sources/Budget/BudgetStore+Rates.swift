import Foundation

extension AccountKind {
    /// Taux fixé par l'État (ou plancher réglementaire) : peut être renseigné automatiquement.
    var hasRegulatedRate: Bool {
        switch self {
        case .livretA, .ldds, .lep, .livretJeune, .pel, .cel: true
        default: false
        }
    }
}

extension Account {
    /// Taux automatique actif (type réglementé et `autoRate` non désactivé).
    var usesAutoRate: Bool { kind.hasRegulatedRate && autoRate != false }
}

@MainActor
extension BudgetStore {
    /// Taux réglementé en vigueur pour ce type de compte (PEL : selon la date d'ouverture).
    func regulatedRate(for account: Account) -> RegulatedRate? {
        guard account.kind.hasRegulatedRate else { return nil }
        return RateService.shared.regulatedRate(kind: account.kind, openingDate: account.openingDate)
    }

    /// Taux affiché : réglementé si automatique, sinon celui saisi.
    func effectiveRate(for account: Account) -> Decimal? {
        if account.usesAutoRate, let regulated = regulatedRate(for: account) { return regulated.rate }
        return account.interestRate
    }

    /// Met à jour les taux publiés si la dernière vérification date de plus de 7 jours.
    func refreshRates() async {
        await RateService.shared.refreshIfNeeded(directory: directory)
    }
}
