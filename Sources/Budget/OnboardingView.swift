import SwiftUI

/// Assistant de démarrage : compte par défaut, récurrentes et ajouts rapides.
/// Seuls les comptes ajoutés via l'éditeur sont enregistrés avant « Commencer ».
struct OnboardingView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    var onFinish: () -> Void

    private enum Step: Int, CaseIterable { case welcome, student, account, recurring, quick, done }

    @State private var step = Step.welcome
    @State private var goingForward = true
    @State private var loaded = false
    @State private var draft = AccountDraft(account: .main)
    @State private var recurring = OnboardingRecurringItem.suggestions
    @State private var quick: [OnboardingQuickItem] = []
    @State private var newAccountDraft: AccountDraft?
    @State private var pendingDelete: Account?
    @State private var isStudent = false
    @State private var izlyOn = true
    @State private var izlyBalance = ""
    @State private var izlyID = UUID().uuidString

    private var isOptional: Bool { step == .recurring || step == .quick }
    private var canContinue: Bool {
        switch step {
        case .account: draft.validated() != nil && (!izlyEnabled || izlyBalanceValid)
        case .recurring: recurring.allSatisfy { !$0.selected || $0.isValid }
        case .quick: quick.allSatisfy(\.isValid)
        default: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .opacity))
                    .padding(.horizontal, theme.padding * 2)
                    .padding(.vertical, theme.padding)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .screenBackground()
        .font(theme.bodyFont)
        .tint(theme.accent)
        .interactiveDismissDisabled()
        .accountDeletionDialog(item: $pendingDelete)
        .sheet(item: $newAccountDraft) { AccountEditorSheet(draft: $0) }
        .onAppear(perform: load)
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 600)
        #endif
    }

    // MARK: Chargement

    /// Reprend l'état actuel du store (compte principal, récurrentes, ajouts rapides).
    private func load() {
        guard !loaded else { return }
        loaded = true
        let main = store.account(id: Account.mainID)
        draft = AccountDraft(account: main)
        draft.nameIsAuto = main.name == Account.main.name
        quick = store.quickExpenses.map { OnboardingQuickItem(existing: $0) }
            + OnboardingQuickItem.suggestions.filter { suggestion in
                !store.quickExpenses.contains { $0.name.caseInsensitiveCompare(suggestion.name) == .orderedSame }
            }
    }

    // MARK: Structure

    private var header: some View {
        HStack {
            Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                .font(theme.captionFont).foregroundStyle(theme.textSecondary)
            HStack(spacing: 4) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? theme.accent : theme.surfaceSecondary)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, theme.padding * 2)
        .padding(.top, theme.padding)
        .frame(maxWidth: 720)
    }

    private var footer: some View {
        HStack(spacing: theme.spacing) {
            if step != .welcome {
                Button("Retour") { go(-1) }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            if isOptional {
                Button("Passer") { skip() }
                    .buttonStyle(.plain).foregroundStyle(theme.textSecondary)
                    .padding(.trailing, theme.spacing)
            }
            Button {
                if step == .done { finish() } else { go(1) }
            } label: {
                Text(step == .done ? "Commencer" : "Continuer")
                    .font(theme.titleFont)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, theme.padding * 1.5)
                    .padding(.vertical, theme.spacing)
                    .background(theme.accent.opacity(canContinue ? 1 : 0.4), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
        }
        .padding(theme.padding * 1.5)
        .padding(.horizontal, theme.padding / 2)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .student: OnboardingStudentStep(isStudent: $isStudent)
        case .account: accountStep
        case .recurring: OnboardingRecurringStep(items: $recurring)
        case .quick: OnboardingQuickStep(items: $quick)
        case .done: summary
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        goingForward = delta > 0
        if step == .student { syncCrous() }
        withAnimation(.smooth(duration: 0.35)) { step = next }
    }

    /// « Passer » : on ignore la sélection de l'étape.
    private func skip() {
        switch step {
        case .recurring: for i in recurring.indices { recurring[i].selected = false }
        case .quick: for i in quick.indices where quick[i].existing == nil { quick[i].selected = false }
        default: break
        }
        go(1)
    }

    // MARK: 1 · Bienvenue

    private var welcome: some View {
        VStack(spacing: theme.padding * 1.5) {
            Image(systemName: "eurosign.circle.fill")
                .font(.system(size: 64, weight: .medium, design: theme.fontDesign))
                .foregroundStyle(theme.heroTextPrimary)
                .frame(width: 128, height: 128)
                .background(
                    LinearGradient(colors: [theme.heroGradientStart, theme.heroGradientEnd],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: theme.cornerRadius * 2, style: .continuous))
                .shadow(color: theme.heroShadowColor, radius: theme.heroShadowRadius, y: theme.cardShadowY)
            Text("Bienvenue dans Budget")
                .font(theme.largeAmountFont).foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)
            Text("Suis tes dépenses, tes revenus et tes comptes au même endroit. Quelques questions pour tout préparer, ça prend une minute.")
                .font(theme.bodyFont).foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, theme.padding * 3)
    }

    // MARK: 2 · Compte par défaut

    private var kind: AccountKind { draft.account.kind }
    private var mainHasTransactions: Bool { store.usageCount(of: store.account(id: Account.mainID)) > 0 }
    private var otherAccounts: [Account] { store.accounts.filter { $0.id != Account.mainID && !$0.isArchived } }

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            OnboardingStepHeader(title: "Ton compte par défaut",
                                 subtitle: "Le compte utilisé par défaut pour tes opérations.")
            preview
            Card { typeSection }
            if !kind.hidesBank { Card { bankSection } }
            Card { nameSection }
            Card { balanceSection }
            otherAccountsSection
            if isStudent && existingIzly == nil {
                OnboardingIzlyCard(isOn: $izlyOn, balanceText: $izlyBalance)
            }
        }
    }

    // MARK: Profil étudiant

    private var existingIzly: Account? { store.accounts.first { $0.kind == .izly } }
    private var izlyEnabled: Bool { isStudent && izlyOn && existingIzly == nil }
    private var izlyBalanceValid: Bool { AccountDraft.isBlank(izlyBalance) || AccountDraft.parse(izlyBalance) != nil }

    /// Ajoute ou retire la suggestion « Repas Crous » selon la réponse.
    private func syncCrous() {
        if isStudent {
            guard !quick.contains(where: \.isCrous) else { return }
            let known = store.categories.contains { $0.id == "restaurants" && !$0.isHidden && $0.kind == .expense }
            quick.insert(.crous(categoryID: known ? "restaurants" : "otherExpense"), at: 0)
        } else {
            quick.removeAll { $0.isCrous }
        }
    }

    private var preview: some View {
        let color = theme.color(for: draft.account)
        let name = draft.account.name.trimmingCharacters(in: .whitespaces)
        let subtitle = [draft.trimmedBank.isEmpty || kind.hidesBank ? nil : draft.trimmedBank, kind.label]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: theme.padding) {
            AccountBadge(account: draft.account, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Nom du compte" : name)
                    .font(theme.titleFont)
                    .foregroundStyle(name.isEmpty ? theme.textTertiary : theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle).font(theme.captionFont).foregroundStyle(theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let balance = draft.parsedBalance {
                Text(balance.euros).font(theme.amountFont).foregroundStyle(theme.textPrimary)
            }
        }
        .padding(theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(theme.badgeFillOpacity), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous).strokeBorder(color, lineWidth: 1.5))
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(theme.captionFont).foregroundStyle(theme.textSecondary)
    }

    private func familyLabel(_ family: AccountFamily) -> String {
        switch family {
        case .current: "Courant"
        case .savings: "Épargne"
        case .investment: "Investissement"
        case .other: "Autre"
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            caption("Type de compte")
            EditorFlowLayout(spacing: theme.spacing) {
                ForEach(AccountFamily.allCases) { family in
                    OnboardingChip(title: familyLabel(family), icon: AccountKind.kinds(in: family).first?.icon,
                                   selected: kind.family == family) {
                        guard kind.family != family, let first = AccountKind.kinds(in: family).first else { return }
                        setKind(first)
                    }
                }
            }
            Divider().overlay(theme.separator)
            EditorFlowLayout(spacing: theme.spacing) {
                ForEach(AccountKind.selectableKinds(in: kind.family, studentEnabled: false, current: kind)) { option in
                    OnboardingChip(title: option.label, icon: option.icon, selected: kind == option) { setKind(option) }
                }
            }
        }
    }

    private func setKind(_ newKind: AccountKind) {
        draft.account.kind = newKind
        draft.refreshName()
    }

    private var bankBinding: Binding<String> {
        Binding(get: { draft.bankText }, set: { draft.bankText = $0; draft.refreshName() })
    }

    private var bankSection: some View {
        let typed = draft.trimmedBank.lowercased()
        let known = store.banks
        let extra = AccountEditorSheet.commonBanks.filter { name in !known.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let suggestions = (known + extra).filter {
            typed.isEmpty || ($0.lowercased().contains(typed) && $0.lowercased() != typed)
        }
        return VStack(alignment: .leading, spacing: theme.spacing) {
            caption("Banque")
            TextField("Banque", text: bankBinding, prompt: Text("Facultatif"))
                .textFieldStyle(.plain).foregroundStyle(theme.textPrimary)
            if !suggestions.isEmpty {
                EditorFlowLayout(spacing: theme.spacing) {
                    ForEach(suggestions, id: \.self) { bank in
                        OnboardingChip(title: bank) { bankBinding.wrappedValue = bank }
                    }
                }
            }
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            caption("Nom")
            TextField("Nom", text: Binding(
                get: { draft.account.name },
                set: { draft.account.name = $0; draft.nameIsAuto = false }
            ), prompt: Text("Nom du compte"))
                .textFieldStyle(.plain).foregroundStyle(theme.textPrimary)
        }
    }

    private var balanceSection: some View {
        let title = mainHasTransactions ? "Solde initial" : (kind.hasMarketValue ? "Versements initiaux" : "Solde actuel")
        return VStack(alignment: .leading, spacing: theme.spacing) {
            HStack {
                Text(title).foregroundStyle(theme.textPrimary)
                Spacer()
                OnboardingNumberField(title: title, text: $draft.balanceText, unit: "€", width: 110)
            }
            caption(mainHasTransactions
                    ? "Ce compte contient déjà des opérations : son solde = solde initial + revenus − dépenses. Peut être négatif."
                    : "Le montant actuellement sur le compte. Les opérations que tu saisiras ensuite s'y ajouteront. Peut être négatif.")
        }
    }

    private var otherAccountsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing) {
            Text("Autres comptes").font(theme.titleFont).foregroundStyle(theme.textPrimary)
            caption("Livret A, épargne, espèces… Facultatif, tu pourras en ajouter plus tard.")
            Card {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    ForEach(otherAccounts) { account in
                        HStack(spacing: theme.spacing) {
                            AccountBadge(account: account, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name).font(theme.bodyFont).foregroundStyle(theme.textPrimary)
                                Text(accountSubtitle(account)).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                            }
                            Spacer()
                            Text(account.initialBalance.euros).font(theme.amountFont).foregroundStyle(theme.textSecondary)
                            Button { pendingDelete = account } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(theme.negative).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .help("Retirer ce compte")
                        }
                        Divider().overlay(theme.separator)
                    }
                    Button {
                        newAccountDraft = AccountDraft(newColorIndex: store.accounts.count % max(theme.categoryPalette.count, 1))
                    } label: {
                        Label("Ajouter un autre compte", systemImage: "plus.circle.fill")
                            .font(theme.bodyFont).foregroundStyle(theme.accent).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 5 · Récapitulatif

    private var selectedRecurring: [OnboardingRecurringItem] { recurring.filter { $0.selected && $0.isValid } }
    private var selectedQuick: [QuickExpense] {
        let izlyID = izlyEnabled ? self.izlyID : existingIzly?.id
        return quick.compactMap { item in
            var item = item
            if item.isCrous { item.accountID = izlyID }
            return item.quickExpense(store: store)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: theme.padding) {
            OnboardingStepHeader(title: "Tout est prêt", subtitle: "Voici ce qui va être configuré. Tu pourras tout modifier ensuite dans l'app.")
            Card {
                VStack(alignment: .leading, spacing: theme.padding) {
                    summaryRow("star.fill", "Compte par défaut", draft.account.name)
                    summaryRow("building.columns.fill", "Autres comptes", onboardingCount(otherAccounts.count + (izlyEnabled ? 1 : 0), "compte", "comptes"))
                    summaryRow("repeat", "Opérations récurrentes", onboardingCount(selectedRecurring.count, "récurrente", "récurrentes"))
                    summaryRow("bolt.fill", "Ajouts rapides", onboardingCount(selectedQuick.count, "ajout rapide", "ajouts rapides"))
                }
            }
        }
    }

    private func summaryRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: theme.spacing) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(theme.badgeFillOpacity), in: .circle)
            Text(title).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).font(theme.amountFont).foregroundStyle(theme.textPrimary).lineLimit(1)
        }
    }

    // MARK: Application

    /// Écrit tout dans le store, puis ferme l'assistant.
    private func finish() {
        guard let main = draft.validated() else { return }
        store.upsertAccount(main)
        if isStudent {
            UserDefaults.standard.set(true, forKey: StudentProfile.enabledKey)
            if izlyEnabled {
                store.upsertAccount(.makeIzly(id: izlyID, balance: AccountDraft.parse(izlyBalance) ?? 0,
                                              existing: store.accounts, paletteCount: theme.categoryPalette.count))
            }
        }
        for item in selectedRecurring {
            guard let amount = item.amount, let day = item.day else { continue }
            let known = store.categories.contains { $0.id == item.categoryID && !$0.isHidden && $0.kind == item.kind }
            store.upsertRecurring(RecurringOperation(
                name: item.trimmedName, amount: amount, kind: item.kind,
                categoryID: known ? item.categoryID : store.fallbackCategory(for: item.kind).id,
                accountID: nil, note: "", frequency: .monthly,
                startDate: OnboardingRecurringItem.nextDate(day: day), endDate: nil,
                isActive: true, lastGeneratedDate: nil))
        }
        store.quickExpenses = selectedQuick
        store.saveSettings()
        onFinish()
    }
}
