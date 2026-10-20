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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Theme.all) { option in
                    let selected = option.id == Theme.named(themeID).id
                    Button {
                        themeID = option.id
                    } label: {
                        SettingsThemePreview(option: option, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Vignette d'un thème : nom, pastilles de sa palette et son accent, sur son fond.
private struct SettingsThemePreview: View {
    let option: Theme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(option.name)
                    .font(option.titleFont)
                    .foregroundStyle(option.textPrimary)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(option.accent)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(option.categoryPalette.prefix(4).enumerated()), id: \.offset) { _, color in
                    Circle().fill(color).frame(width: 12, height: 12)
                }
                Capsule().fill(option.accent).frame(width: 18, height: 8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(option.background, in: .rect(cornerRadius: option.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: option.smallCornerRadius)
                .stroke(selected ? option.accent : option.separator, lineWidth: selected ? 2 : 1)
        )
        .contentShape(.rect)
    }
}

#if os(macOS)
import ServiceManagement

/// Section « Barre des menus » : icône facultative, ouverture au démarrage, raccourci global.
struct SettingsMenuBarSection: View {
    @AppStorage(MenuBarSettings.enabled) private var enabled = false
    @AppStorage(MenuBarSettings.hotKey) private var hotKeyEnabled = true
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?
    @Environment(\.theme) private var theme

    var body: some View {
        Section {
            Toggle("Afficher Budget dans la barre des menus", isOn: $enabled)
            if enabled {
                Toggle("Ouvrir au démarrage du Mac", isOn: Binding(
                    get: { status == .enabled || status == .requiresApproval },
                    set: setLaunchAtLogin
                ))
                if status == .requiresApproval {
                    HStack {
                        Text("À autoriser dans Réglages Système › Général › Ouverture.")
                            .font(theme.captionFont).foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button("Ouvrir les Réglages Système") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(theme.captionFont).foregroundStyle(theme.negative)
                }
                Toggle("Raccourci global ⌥⌘B", isOn: $hotKeyEnabled)
            }
        } header: {
            Text("Barre des menus")
        } footer: {
            Text("L'icône reste disponible même fenêtre fermée. Quitter Budget (⌘Q) l'arrête.")
                .font(theme.captionFont).foregroundStyle(theme.textSecondary)
        }
        .onAppear { status = SMAppService.mainApp.status }
        .onChange(of: enabled) { status = SMAppService.mainApp.status; errorMessage = nil }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        errorMessage = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = "Impossible de modifier l'ouverture au démarrage. L'app n'étant pas signée par Apple, "
                + "cela peut échouer si elle n'est pas dans le dossier Applications. (\(error.localizedDescription))"
        }
        status = SMAppService.mainApp.status
    }
}
#endif
