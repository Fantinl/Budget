import SwiftUI

/// Liste des raccourcis clavier et astuces de saisie.
struct ShortcutsView: View {
    @Environment(\.theme) private var theme

    private struct Item: Identifiable {
        let action: String
        let keys: [String]
        var id: String { action }
    }

    private struct Group: Identifiable {
        let title: String
        let icon: String
        let items: [Item]
        var id: String { title }
    }

    private let groups: [Group] = [
        Group(title: "Général", icon: "gearshape", items: [
            Item(action: "Réglages", keys: ["⌘", ","]),
            Item(action: "Raccourcis clavier", keys: ["⌘", "/"]),
            Item(action: "Annuler", keys: ["⌘", "Z"]),
            Item(action: "Rétablir", keys: ["⇧", "⌘", "Z"]),
            Item(action: "Panneau de la barre des menus (si activée)", keys: ["⌥", "⌘", "B"]),
        ]),
        Group(title: "Opérations", icon: "list.bullet", items: [
            Item(action: "Nouvelle opération", keys: ["⌘", "N"]),
            Item(action: "Saisie express", keys: ["⌘", "E"]),
            Item(action: "Rechercher", keys: ["⌘", "F"]),
            Item(action: "Ajout rapide (dans l'ordre affiché)", keys: ["⌘", "1 … 9"]),
        ]),
        Group(title: "Navigation", icon: "calendar", items: [
            Item(action: "Mois précédent", keys: ["⌘", "←"]),
            Item(action: "Mois suivant", keys: ["⌘", "→"]),
        ]),
        Group(title: "Sélection", icon: "checkmark.circle", items: [
            Item(action: "Ajouter / retirer une ligne", keys: ["⌘", "clic"]),
            Item(action: "Sélectionner une plage", keys: ["⇧", "clic"]),
            Item(action: "Tout sélectionner", keys: ["⌘", "A"]),
            Item(action: "Supprimer la sélection", keys: ["⌫"]),
            Item(action: "Annuler la sélection / vider la recherche", keys: ["Échap"]),
        ]),
        Group(title: "Saisie", icon: "sparkles", items: [
            Item(action: "Enregistrer la saisie express", keys: ["↩"]),
            Item(action: "Ouvrir le formulaire complet", keys: ["⌥", "↩"]),
        ]),
    ]

    private let tips: [(icon: String, title: String, text: String)] = [
        ("function", "Calcul dans les montants", "Tape « 12,5+8 » dans un champ montant : 20,50 €."),
        ("sparkles", "Exemples de saisie express", "« café 2,5 », « courses 45 hier », « +1800 salaire »."),
        ("square.and.arrow.down", "Importer un relevé", "Glisse le fichier CSV de ta banque sur la fenêtre."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.padding) {
                ForEach(groups) { group in section(group) }
                tipsSection
            }
            .padding(theme.padding)
        }
        .screenBackground()
        .navigationTitle("Raccourcis clavier")
    }

    private func header(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(theme.titleFont)
            .foregroundStyle(theme.textPrimary)
            .padding(.leading, theme.spacing / 2)
    }

    private func section(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing / 2) {
            header(group.title, icon: group.icon)
            Card(padded: false) {
                VStack(spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(theme.separator) }
                        HStack(spacing: theme.spacing) {
                            Text(item.action)
                                .font(theme.bodyFont)
                                .foregroundStyle(theme.textPrimary)
                            Spacer(minLength: theme.spacing)
                            HStack(spacing: 4) {
                                ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in keyCap(key) }
                            }
                        }
                        .padding(.horizontal, theme.padding)
                        .padding(.vertical, theme.spacing)
                    }
                }
            }
        }
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing / 2) {
            header("Astuces", icon: "lightbulb")
            Card {
                VStack(alignment: .leading, spacing: theme.spacing) {
                    ForEach(tips, id: \.title) { tip in
                        HStack(alignment: .top, spacing: theme.spacing) {
                            Image(systemName: tip.icon)
                                .foregroundStyle(theme.accent)
                                .frame(width: theme.iconSize)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                    .font(theme.bodyFont)
                                    .foregroundStyle(theme.textPrimary)
                                Text(tip.text)
                                    .font(theme.captionFont)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Une touche de clavier dessinée en petite capsule.
    private func keyCap(_ key: String) -> some View {
        Text(key)
            .font(theme.captionFont.monospaced())
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, theme.spacing)
            .frame(minWidth: 26, minHeight: 24)
            .background(theme.surfaceSecondary, in: .rect(cornerRadius: theme.cornerRadius / 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.cornerRadius / 2, style: .continuous)
                .strokeBorder(theme.separator, lineWidth: 1))
    }
}
