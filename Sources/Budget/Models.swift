import Foundation
import SwiftUI

enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case expense, income

    var id: Self { self }

    var label: String {
        switch self {
        case .expense: "Dépense"
        case .income: "Revenu"
        }
    }
}

/// Catégorie définie par l'utilisateur (modifiable dans les réglages).
struct Category: Identifiable, Codable, Hashable {
    /// Identifiant stable, enregistré dans chaque opération. Les catégories par défaut gardent
    /// les identifiants de la première version (« groceries »…), ce qui assure la compatibilité.
    var id: String
    var label: String
    var icon: String              // nom de symbole SF
    var kind: TransactionKind
    var colorIndex: Int           // index dans `theme.categoryPalette`
    var isHidden = false          // masquée : n'est plus proposée, mais les anciennes opérations la gardent
    /// Budget mensuel (plafond de dépenses), nil = pas de budget.
    var monthlyBudget: Decimal?

    init(id: String = UUID().uuidString, label: String, icon: String, kind: TransactionKind, colorIndex: Int,
         isHidden: Bool = false, monthlyBudget: Decimal? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.kind = kind
        self.colorIndex = colorIndex
        self.isHidden = isHidden
        self.monthlyBudget = monthlyBudget
    }

    /// Utilisée quand une opération pointe vers une catégorie supprimée.
    static func unknown(id: String) -> Category {
        Category(id: id, label: "Sans catégorie", icon: "questionmark.circle", kind: .expense, colorIndex: -1)
    }

    static let defaults: [Category] = [
        Category(id: "groceries", label: "Courses", icon: "cart.fill", kind: .expense, colorIndex: 0),
        Category(id: "housing", label: "Logement", icon: "house.fill", kind: .expense, colorIndex: 1),
        Category(id: "transport", label: "Transport", icon: "car.fill", kind: .expense, colorIndex: 2),
        Category(id: "restaurants", label: "Restaurants", icon: "fork.knife", kind: .expense, colorIndex: 3),
        Category(id: "leisure", label: "Loisirs", icon: "gamecontroller.fill", kind: .expense, colorIndex: 4),
        Category(id: "health", label: "Santé", icon: "heart.fill", kind: .expense, colorIndex: 5),
        Category(id: "shopping", label: "Shopping", icon: "bag.fill", kind: .expense, colorIndex: 6),
        Category(id: "subscriptions", label: "Abonnements", icon: "repeat", kind: .expense, colorIndex: 7),
        Category(id: "otherExpense", label: "Autre", icon: "ellipsis.circle.fill", kind: .expense, colorIndex: 8),
        Category(id: "salary", label: "Salaire", icon: "banknote.fill", kind: .income, colorIndex: 9),
        Category(id: "refund", label: "Remboursement", icon: "arrow.uturn.backward.circle.fill", kind: .income, colorIndex: 10),
        Category(id: "otherIncome", label: "Autre revenu", icon: "plus.circle.fill", kind: .income, colorIndex: 11),
    ]
}

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Decimal
    var kind: TransactionKind
    var categoryID: String
    var note: String
    var date: Date
    /// Compte de l'opération ; nil = compte principal (`Account.mainID`). Absent des anciens fichiers.
    var accountID: String?
    /// Renseigné si l'opération a été créée automatiquement par une opération récurrente.
    var recurringID: UUID?
    /// Virement entre deux comptes : deux opérations partagent cet identifiant
    /// (une dépense sur le compte source, un revenu sur le compte destination).
    var transferID: UUID?

    // La clé JSON reste « category » pour relire les fichiers de la première version.
    enum CodingKeys: String, CodingKey {
        case id, amount, kind, note, date, accountID, recurringID, transferID
        case categoryID = "category"
    }

    var isTransfer: Bool { transferID != nil }
    /// Vraie dépense / vrai revenu : les virements entre comptes ne comptent ni dans l'un ni dans l'autre
    /// (ils changent les soldes des comptes, pas le budget).
    var isSpending: Bool { kind == .expense && !isTransfer }
    var isEarning: Bool { kind == .income && !isTransfer }

    /// Compte effectif (le compte principal si non renseigné).
    var resolvedAccountID: String { accountID ?? Account.mainID }

    /// Montant négatif pour une dépense, positif pour un revenu.
    var signedAmount: Decimal { kind == .expense ? -amount : amount }

    static func empty(categoryID: String) -> Transaction {
        Transaction(amount: 0, kind: .expense, categoryID: categoryID, note: "", date: .now)
    }
}

// MARK: - Comptes

/// Grande famille de compte : sert à regrouper les comptes sur la page Comptes.
enum AccountFamily: String, CaseIterable, Identifiable {
    case current, savings, investment, other

    var id: Self { self }

    var label: String {
        switch self {
        case .current: "Comptes courants"
        case .savings: "Épargne"
        case .investment: "Investissements"
        case .other: "Autres"
        }
    }
}

/// Type précis de compte (produits français). Les valeurs brutes des premiers types
/// (checking, savings, cash, card) sont conservées pour relire les anciens fichiers.
enum AccountKind: String, Codable, CaseIterable, Identifiable {
    // Courant
    case checking
    // Épargne
    case livretA, ldds, lep, livretJeune, pel, cel, savings, assuranceVie
    // Investissement
    case pea, peaPme, compteTitres, per, crypto
    // Autres
    case cash, card

    var id: Self { self }

    var family: AccountFamily {
        switch self {
        case .checking: .current
        case .livretA, .ldds, .lep, .livretJeune, .pel, .cel, .savings, .assuranceVie: .savings
        case .pea, .peaPme, .compteTitres, .per, .crypto: .investment
        case .cash, .card: .other
        }
    }

    var label: String {
        switch self {
        case .checking: "Compte courant"
        case .livretA: "Livret A"
        case .ldds: "LDDS"
        case .lep: "LEP"
        case .livretJeune: "Livret Jeune"
        case .pel: "PEL"
        case .cel: "CEL"
        case .savings: "Compte sur livret"
        case .assuranceVie: "Assurance vie"
        case .pea: "PEA"
        case .peaPme: "PEA-PME"
        case .compteTitres: "Compte-titres"
        case .per: "PER"
        case .crypto: "Crypto"
        case .cash: "Espèces"
        case .card: "Carte prépayée"
        }
    }

    var icon: String {
        switch self {
        case .checking: "building.columns.fill"
        case .livretA, .ldds, .lep, .livretJeune, .savings: "banknote.fill"
        case .pel, .cel: "house.fill"
        case .assuranceVie: "shield.fill"
        case .pea, .peaPme, .compteTitres: "chart.line.uptrend.xyaxis"
        case .per: "figure.walk"
        case .crypto: "bitcoinsign.circle.fill"
        case .cash: "dollarsign.circle.fill"
        case .card: "creditcard.fill"
        }
    }

    /// Plafond réglementaire de dépôts (2026), nil si aucun. Pour le PEA : plafond de versements.
    var ceiling: Decimal? {
        switch self {
        case .livretA: 22_950
        case .ldds: 12_000
        case .lep: 10_000
        case .livretJeune: 1_600
        case .pel: 61_200
        case .cel: 15_300
        case .pea: 150_000
        case .peaPme: 225_000   // plafond commun PEA + PEA-PME
        default: nil
        }
    }

    /// Placement dont la valeur fluctue : on saisit une valorisation en plus des versements.
    var hasMarketValue: Bool { family == .investment || self == .assuranceVie }

    static func kinds(in family: AccountFamily) -> [AccountKind] {
        allCases.filter { $0.family == family }
    }
}

/// Compte bancaire, livret, placement ou porte-monnaie.
/// Solde = solde initial + opérations du compte ; pour un placement, la valorisation saisie prime.
struct Account: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var kind: AccountKind
    var colorIndex: Int           // index dans `theme.categoryPalette`
    var initialBalance: Decimal
    var isArchived: Bool
    /// Banque ou établissement (« Boursorama », « Crédit Agricole »…). Sert au regroupement par banque.
    var bank: String?
    /// Taux annuel en % (ex. 2.4), facultatif.
    var interestRate: Decimal?
    /// Valeur actuelle saisie pour un placement (PEA, assurance vie…), et sa date.
    var marketValue: Decimal?
    var marketValueDate: Date?
    /// nil/true = taux réglementé automatique (si le type le permet) ; false = taux saisi à la main.
    var autoRate: Bool?
    /// Date d'ouverture d'un PEL : détermine son taux.
    var openingDate: Date?

    init(id: String = UUID().uuidString, name: String, kind: AccountKind, colorIndex: Int,
         initialBalance: Decimal = 0, isArchived: Bool = false, bank: String? = nil,
         interestRate: Decimal? = nil, marketValue: Decimal? = nil, marketValueDate: Date? = nil,
         autoRate: Bool? = nil, openingDate: Date? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorIndex = colorIndex
        self.initialBalance = initialBalance
        self.isArchived = isArchived
        self.bank = bank
        self.interestRate = interestRate
        self.marketValue = marketValue
        self.marketValueDate = marketValueDate
        self.autoRate = autoRate
        self.openingDate = openingDate
    }

    // Type inconnu (fichier d'une version future) → compte courant, plutôt que d'échouer.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = AccountKind(rawValue: (try? c.decode(String.self, forKey: .kind)) ?? "") ?? .checking
        colorIndex = try c.decode(Int.self, forKey: .colorIndex)
        initialBalance = try c.decode(Decimal.self, forKey: .initialBalance)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        bank = try c.decodeIfPresent(String.self, forKey: .bank)
        interestRate = try c.decodeIfPresent(Decimal.self, forKey: .interestRate)
        marketValue = try c.decodeIfPresent(Decimal.self, forKey: .marketValue)
        marketValueDate = try c.decodeIfPresent(Date.self, forKey: .marketValueDate)
        autoRate = try c.decodeIfPresent(Bool.self, forKey: .autoRate)
        openingDate = try c.decodeIfPresent(Date.self, forKey: .openingDate)
    }

    /// Libellé de banque pour le regroupement.
    var bankLabel: String { bank.flatMap { $0.isEmpty ? nil : $0 } ?? "Sans banque" }

    /// Compte principal : reçoit les opérations sans compte (toutes celles d'avant les comptes).
    static let mainID = "main"
    static let main = Account(id: mainID, name: "Compte courant", kind: .checking, colorIndex: 2)
}

// MARK: - Opérations récurrentes

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly

    var id: Self { self }

    var label: String {
        switch self {
        case .weekly: "Chaque semaine"
        case .monthly: "Chaque mois"
        case .quarterly: "Chaque trimestre"
        case .yearly: "Chaque année"
        }
    }
}

/// Opération qui revient à date fixe (loyer le 5, salaire le 28…). Les opérations sont créées
/// automatiquement à chaque échéance passée (voir BudgetStore+Recurring.swift).
struct RecurringOperation: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Decimal
    var kind: TransactionKind
    var categoryID: String
    var accountID: String?
    var note: String
    var frequency: RecurrenceFrequency
    /// Première échéance ; son jour (et son mois pour l'annuel) fixe les suivantes.
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    /// Dernière échéance déjà transformée en opération (nil = aucune encore).
    var lastGeneratedDate: Date?
}

/// Dépense habituelle, ajoutée en un clic (« Café 2,50 € »…). Paramétrable dans les réglages.
struct QuickExpense: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var amount: Decimal
    var kind: TransactionKind = .expense
    var categoryID: String
    var note = ""
    /// Compte crédité/débité ; nil = compte principal.
    var accountID: String? = nil

    /// Opération prête à enregistrer, datée de maintenant.
    func makeTransaction(date: Date = .now) -> Transaction {
        Transaction(amount: amount, kind: kind, categoryID: categoryID, note: note.isEmpty ? name : note,
                    date: date, accountID: accountID)
    }

    static let defaults: [QuickExpense] = [
        QuickExpense(name: "Café", amount: 2.5, categoryID: "restaurants"),
        QuickExpense(name: "Boulangerie", amount: 3, categoryID: "groceries"),
        QuickExpense(name: "Essence", amount: 60, categoryID: "transport"),
    ]
}

extension Decimal {
    var euros: String { formatted(.currency(code: "EUR")) }
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension Date {
    var startOfMonth: Date {
        Calendar.current.dateInterval(of: .month, for: self)?.start ?? self
    }

    func addingMonths(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: n, to: self) ?? self
    }
}
