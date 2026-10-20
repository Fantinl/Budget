import Foundation

// Repas Izly : décompte automatique d'un repas par jour choisi, revue hebdomadaire et ajout en masse.
extension BudgetStore {
    /// Garde-fou : nombre maximal de repas créés par appel.
    private static let maxMealsPerCall = 400
    /// Nombre de jours après lequel la revue est proposée.
    static let mealReviewDelay = 7
    /// Nombre maximal de jours affichés dans la revue.
    static let mealReviewSpan = 14

    // MARK: Génération automatique

    /// Crée les repas des jours passés (jusqu'à aujourd'hui inclus) non encore décomptés. Appelée au lancement.
    func generateDueMeals(now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var created: [Transaction] = []
        var changed = false

        for index in accounts.indices {
            let account = accounts[index]
            guard account.kind == .izly, !account.isArchived,
                  let plan = account.mealPlan, plan.isEnabled else { continue }
            var from = calendar.startOfDay(for: plan.startDate)
            if let last = plan.lastGeneratedDate,
               let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) {
                from = max(from, next)
            }
            guard from <= today else { continue }

            let taken = mealDays(of: account.id, calendar: calendar)
            let budget = Self.maxMealsPerCall - created.count
            guard budget > 0 else { break }
            let (meals, lastDay) = Self.meals(for: account, plan: plan, from: from, to: today,
                                              skipping: taken, limit: budget, categoryID: mealCategoryID(plan.categoryID),
                                              calendar: calendar)
            created.append(contentsOf: meals)
            if let lastDay, lastDay != plan.lastGeneratedDate {
                accounts[index].mealPlan?.lastGeneratedDate = lastDay
                changed = true
            }
        }

        if !created.isEmpty {
            transactions.append(contentsOf: created)
            saveTransactions()
        }
        if changed { saveSettings() }
    }

    /// Repas à créer sur la période ; renvoie aussi le dernier jour parcouru (pour reprendre après le garde-fou).
    private static func meals(for account: Account, plan: MealPlan, from: Date, to: Date, skipping taken: Set<Date>,
                              limit: Int, categoryID: String, calendar: Calendar) -> ([Transaction], Date?) {
        var result: [Transaction] = []
        var day = from
        var lastDay: Date?
        while day <= to {
            if result.count >= limit { break }
            lastDay = day
            if plan.weekdays.contains(calendar.component(.weekday, from: day)), !taken.contains(day) {
                result.append(makeMeal(on: day, price: plan.price, categoryID: categoryID,
                                       accountID: account.id, calendar: calendar))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (result, lastDay)
    }

    private static func makeMeal(on day: Date, price: Decimal, categoryID: String, accountID: String, calendar: Calendar) -> Transaction {
        var meal = Transaction(
            amount: price, kind: .expense, categoryID: categoryID, note: "Repas Crous",
            date: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day,
            accountID: storedAccountID(accountID))
        meal.isAutoMeal = true
        return meal
    }

    /// Catégorie demandée si elle existe, sinon « Autre ».
    private func mealCategoryID(_ requested: String) -> String {
        categories.contains { $0.id == requested } ? requested : Self.fallbackID(for: .expense)
    }

    /// Débuts de jour où le compte a déjà un repas automatique.
    private func mealDays(of accountID: String, calendar: Calendar = .current) -> Set<Date> {
        Set(transactions.filter { $0.isAutoMeal == true && $0.resolvedAccountID == accountID }
            .map { calendar.startOfDay(for: $0.date) })
    }

    // MARK: Lecture

    /// Repas automatiques du compte sur l'intervalle, du plus ancien au plus récent.
    func meals(of account: Account, in interval: DateInterval) -> [Transaction] {
        transactions
            .filter { $0.isAutoMeal == true && $0.resolvedAccountID == account.id && interval.contains($0.date) }
            .sorted { $0.date < $1.date }
    }

    /// Nombre de repas que permet le solde actuel (0 si prix nul ou solde négatif).
    func mealsRemaining(of account: Account) -> Int {
        let price = account.mealPlan?.price ?? StudentProfile.defaultMealPrice
        let balance = balance(of: account)
        guard price > 0, balance > 0 else { return 0 }
        return NSDecimalNumber(decimal: balance / price).intValue
    }

    // MARK: Ajout / suppression en masse

    /// Ajoute un repas par jour de `weekdays` entre `from` et `to` (inclus), en sautant les jours déjà décomptés.
    @discardableResult
    func addMeals(to account: Account, from: Date, to: Date, weekdays: Set<Int>, price: Decimal) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        guard start <= end, price > 0, !weekdays.isEmpty else { return 0 }
        var plan = MealPlan()
        plan.price = price
        plan.weekdays = weekdays
        let (meals, _) = Self.meals(for: account, plan: plan, from: start, to: end,
                                    skipping: mealDays(of: account.id, calendar: calendar),
                                    limit: Self.maxMealsPerCall,
                                    categoryID: mealCategoryID(account.mealPlan?.categoryID ?? plan.categoryID),
                                    calendar: calendar)
        guard !meals.isEmpty else { return 0 }
        registerUndo("Ajouter des repas")
        transactions.append(contentsOf: meals)
        saveTransactions()
        return meals.count
    }

    /// Nombre de repas qu'ajouterait `addMeals` (aperçu).
    func mealsToAdd(to account: Account, from: Date, to: Date, weekdays: Set<Int>) -> Int {
        let calendar = Calendar.current
        let taken = mealDays(of: account.id, calendar: calendar)
        var day = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        var count = 0
        while day <= end, count < Self.maxMealsPerCall {
            if weekdays.contains(calendar.component(.weekday, from: day)), !taken.contains(day) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// Supprime des repas (annulable).
    @discardableResult
    func removeMeals(ids: Set<UUID>) -> Int {
        let count = transactions.filter { ids.contains($0.id) && $0.isAutoMeal == true }.count
        guard count > 0 else { return 0 }
        registerUndo("Supprimer des repas")
        transactions.removeAll { ids.contains($0.id) && $0.isAutoMeal == true }
        saveTransactions()
        return count
    }

    // MARK: Revue hebdomadaire

    /// Premier jour de la période non revue.
    private func reviewStart(of plan: MealPlan, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: plan.startDate)
        guard let last = plan.lastReviewDate,
              let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return start }
        return max(start, next)
    }

    /// Compte Izly à revoir : plan actif, dernière revue (ou début) d'au moins 7 jours, repas à vérifier.
    func needsMealReview(now: Date = .now) -> Account? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return activeAccounts.first { account in
            guard account.kind == .izly, let plan = account.mealPlan, plan.isEnabled else { return false }
            let reference = calendar.startOfDay(for: plan.lastReviewDate ?? plan.startDate)
            guard let days = calendar.dateComponents([.day], from: reference, to: today).day,
                  days >= Self.mealReviewDelay else { return false }
            let from = reviewStart(of: plan, calendar: calendar)
            guard let end = calendar.date(byAdding: .day, value: 1, to: today) else { return false }
            return !meals(of: account, in: DateInterval(start: from, end: max(end, from))).isEmpty
        }
    }

    /// Note que la période jusqu'à aujourd'hui a été revue.
    func markMealsReviewed(account: Account, now: Date = .now) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }), accounts[index].mealPlan != nil else { return }
        accounts[index].mealPlan?.lastReviewDate = Calendar.current.startOfDay(for: now)
        saveSettings()
    }

    /// Jours proposés à la revue (au plus 14, du plus ancien au plus récent) : jours du plan et jours avec repas.
    func mealReviewDays(of account: Account, now: Date = .now) -> [Date] {
        guard let plan = account.mealPlan else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var from = reviewStart(of: plan, calendar: calendar)
        if let limit = calendar.date(byAdding: .day, value: -(Self.mealReviewSpan - 1), to: today) { from = max(from, limit) }
        let withMeal = mealDays(of: account.id, calendar: calendar)
        var result: [Date] = []
        var day = from
        while day <= today {
            if plan.weekdays.contains(calendar.component(.weekday, from: day)) || withMeal.contains(day) { result.append(day) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Applique la revue en une seule annulation : `present` = jours où l'on a mangé parmi `days`.
    func applyMealReview(account: Account, days: [Date], present: Set<Date>, now: Date = .now) {
        let calendar = Calendar.current
        let plan = account.mealPlan ?? MealPlan()
        let category = mealCategoryID(plan.categoryID)
        let dayList = days.map { calendar.startOfDay(for: $0) }
        let daySet = Set(dayList)
        let wanted = Set(present.map { calendar.startOfDay(for: $0) })
        let existing = transactions.filter {
            $0.isAutoMeal == true && $0.resolvedAccountID == account.id && daySet.contains(calendar.startOfDay(for: $0.date))
        }
        let have = Set(existing.map { calendar.startOfDay(for: $0.date) })
        let doomed = Set(existing.filter { !wanted.contains(calendar.startOfDay(for: $0.date)) }.map(\.id))
        let added = daySet.intersection(wanted).subtracting(have).sorted().map {
            Self.makeMeal(on: $0, price: plan.price, categoryID: category, accountID: account.id, calendar: calendar)
        }
        registerUndo("Revue des repas")
        if !doomed.isEmpty || !added.isEmpty {
            transactions.removeAll { doomed.contains($0.id) }
            transactions.append(contentsOf: added)
            saveTransactions()
        }
        markMealsReviewed(account: account, now: now)
    }

    // MARK: Opérations Izly masquées

    /// Les opérations d'un compte Izly n'apparaissent pas individuellement dans l'écran Opérations
    /// (elles restent dans le compte, le résumé du mois, les budgets et les statistiques).
    func isHiddenFromOperations(_ transaction: Transaction) -> Bool {
        accounts.first { $0.id == transaction.resolvedAccountID }?.kind == .izly
    }

    /// Dépenses Izly du mois (pour la ligne récapitulative) : nombre et total.
    func izlySpending(in transactions: [Transaction]) -> (count: Int, total: Decimal) {
        let spending = transactions.filter { isHiddenFromOperations($0) && $0.isSpending }
        return (spending.count, spending.reduce(Decimal(0)) { $0 + $1.amount })
    }
}

/// Lit un prix saisi (« 1 », « 1,50 ») ; nil si vide, invalide ou ≤ 0.
func parseMealPrice(_ text: String) -> Decimal? {
    let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { !$0.isWhitespace }
    guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
    return value
}
