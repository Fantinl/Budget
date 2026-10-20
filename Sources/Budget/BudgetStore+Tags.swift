import SwiftUI

// Tags : étiquettes libres posées sur les opérations, en plus de la catégorie.
extension BudgetStore {
    func tag(id: String) -> Tag? { tags.first { $0.id == id } }

    /// Tags d'une opération, dans l'ordre de `tags` (les identifiants inconnus sont ignorés).
    func tags(of transaction: Transaction) -> [Tag] {
        guard let ids = transaction.tagIDs, !ids.isEmpty else { return [] }
        return tags.filter { ids.contains($0.id) }
    }

    /// Nombre d'opérations portant ce tag.
    func usageCount(of tag: Tag) -> Int {
        transactions.reduce(0) { $0 + (($1.tagIDs ?? []).contains(tag.id) ? 1 : 0) }
    }

    func upsertTag(_ tag: Tag) {
        registerUndo("Modifier le tag")
        if let index = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[index] = tag
        } else {
            tags.append(tag)
        }
        saveSettings()
    }

    /// Supprime le tag et le retire des opérations (qui sont conservées).
    func deleteTag(_ tag: Tag) {
        registerUndo("Supprimer le tag")
        var changed = false
        for index in transactions.indices {
            guard var ids = transactions[index].tagIDs, ids.contains(tag.id) else { continue }
            ids.removeAll { $0 == tag.id }
            transactions[index].tagIDs = ids.isEmpty ? nil : ids
            changed = true
        }
        if changed { saveTransactions() }
        tags.removeAll { $0.id == tag.id }
        saveSettings()
    }

    func moveTags(from source: IndexSet, to destination: Int) {
        registerUndo("Réordonner les tags")
        tags.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }

    /// Crée un tag, sauf si un tag du même nom existe (casse et accents ignorés) : il est alors renvoyé.
    @discardableResult
    func addTag(named name: String) -> Tag {
        let clean = Self.tagKey(name)
        if let existing = tags.first(where: { Self.tagKey($0.name) == clean }) { return existing }
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).drop { $0 == "#" }
        let tag = Tag(name: String(displayName), colorIndex: tags.count)
        upsertTag(tag)
        return tag
    }

    /// Remplace les tags de plusieurs opérations (nil si la liste est vide).
    func setTags(_ ids: [String], for transactionIDs: Set<UUID>) {
        registerUndo("Modifier les tags")
        for index in transactions.indices where transactionIDs.contains(transactions[index].id) {
            transactions[index].tagIDs = ids.isEmpty ? nil : ids
        }
        saveTransactions()
    }

    private static func tagKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { $0 == "#" }
            .description
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

extension Theme {
    func color(for tag: Tag) -> Color {
        categoryPalette.indices.contains(tag.colorIndex) ? categoryPalette[tag.colorIndex] : categoryFallback
    }
}

/// Petite capsule colorée affichant un tag.
struct TagChip: View {
    @Environment(\.theme) private var theme
    let text: String
    let color: Color
    var selected = true

    var body: some View {
        Text(text)
            .font(theme.captionFont)
            .foregroundStyle(theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, theme.spacing)
            .padding(.vertical, 3)
            .background(color.opacity(selected ? 0.25 : 0.1), in: .capsule)
            .overlay(Capsule().stroke(selected ? color : .clear, lineWidth: 1))
    }
}
