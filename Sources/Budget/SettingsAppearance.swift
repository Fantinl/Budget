import SwiftUI

/// Section « Apparence » : choix du style.
struct SettingsAppearanceSection: View {
    @AppStorage("themeID") private var themeID = Theme.current.id
    @AppStorage("appearance") private var appearance = AppearanceMode.system
    @AppStorage(SidebarFigures.enabled) private var showFigures = true
    @AppStorage(SidebarFigures.wealth) private var showWealth = true
    @AppStorage(SidebarFigures.spent) private var showSpent = true
    @AppStorage(SidebarFigures.income) private var showIncome = false
    @AppStorage(SidebarFigures.balance) private var showBalance = true
    @AppStorage(SidebarFigures.monthCount) private var showMonthCount = true
    @AppStorage(SidebarFigures.accountCount) private var showAccountCount = false
    @Environment(\.theme) private var theme

    var body: some View {
        Section {
            Toggle("Afficher des chiffres", isOn: $showFigures)
            if showFigures {
                Toggle("Patrimoine", isOn: $showWealth)
                Toggle("Dépensé ce mois-ci", isOn: $showSpent)
                Toggle("Revenus du mois", isOn: $showIncome)
                Toggle("Solde du mois", isOn: $showBalance)
                Toggle("Nombre d'opérations du mois (à côté d'Opérations)", isOn: $showMonthCount)
                Toggle("Nombre de comptes (à côté de Comptes)", isOn: $showAccountCount)
            }
        } header: {
            Text("Barre latérale")
        } footer: {
            Text("Chiffres affichés en haut de la barre latérale.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
        }

        Section("Apparence") {
            Picker("Mode", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .font(theme.bodyFont)

            ForEach(Theme.all) { option in
                Button {
                    themeID = option.id
                } label: {
                    HStack(spacing: theme.spacing) {
                        SettingsThemePreview(option: option)
                        Text(option.name)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        if option.id == Theme.named(themeID).id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Aperçu d'un thème : pastilles de sa palette et son accent sur son fond.
private struct SettingsThemePreview: View {
    let option: Theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(option.categoryPalette.prefix(4).enumerated()), id: \.offset) { _, color in
                Circle().fill(color).frame(width: 12, height: 12)
            }
            Capsule().fill(option.accent).frame(width: 18, height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(option.background, in: .rect(cornerRadius: option.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: option.smallCornerRadius)
                .stroke(option.separator, lineWidth: 1)
        )
    }
}
