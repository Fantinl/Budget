import SwiftUI

/// Gestion des tags : liste réordonnable, ajout, édition (nom, couleur) et suppression.
struct SettingsTagsView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @State private var editing: SettingsTagDraft?
    @State private var pendingDelete: Tag?

    var body: some View {
        List {
            Text("Les tags complètent la catégorie : #vacances, #remboursable, #cadeau… Une opération peut en avoir plusieurs.")
                .font(theme.captionFont)
                .foregroundStyle(theme.textSecondary)
                .listRowBackground(Color.clear)
            Section {
                ForEach(store.tags) { tag in row(tag) }
                    .onMove { store.moveTags(from: $0, to: $1) }
                Button {
                    editing = SettingsTagDraft()
                } label: {
                    Label {
                        Text("Ajouter un tag")
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                    } icon: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(theme.surface)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .tint(theme.accent)
        .navigationTitle("Tags")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
        #endif
        .sheet(item: $editing) { SettingsTagSheet(draft: $0) }
        .tagDeletionDialog(item: $pendingDelete)
    }

    private func reorder(_ tag: Tag, _ movement: ReorderMove) {
        guard let index = store.tags.firstIndex(where: { $0.id == tag.id }) else { return }
        store.moveTags(from: [index], to: movement.destination(from: index, count: store.tags.count))
    }

    private func row(_ tag: Tag) -> some View {
        let index = store.tags.firstIndex { $0.id == tag.id } ?? 0
        let canUp = index > 0
        let canDown = index < store.tags.count - 1
        let usage = store.usageCount(of: tag)
        return HStack(spacing: theme.spacing) {
            ReorderButtons(canMoveUp: canUp, canMoveDown: canDown) { reorder(tag, $0) }
            Button {
                editing = SettingsTagDraft(tag: tag)
            } label: {
                HStack(spacing: theme.spacing) {
                    Circle().fill(theme.color(for: tag)).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.name)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        Text(usage == 0 ? "Aucune opération" : usage == 1 ? "1 opération" : "\(usage) opérations")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            TagTrashButton { pendingDelete = tag }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = tag } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .contextMenu {
            ReorderMenuItems(canMoveUp: canUp, canMoveDown: canDown) { reorder(tag, $0) }
            Divider()
            Button("Modifier") { editing = SettingsTagDraft(tag: tag) }
            Button("Supprimer…", role: .destructive) { pendingDelete = tag }
        }
    }
}

/// Bouton poubelle discret, rouge au survol.
private struct TagTrashButton: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .foregroundStyle(hovering ? theme.negative : theme.textTertiary)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Supprimer le tag")
        .accessibilityLabel("Supprimer le tag")
    }
}

/// Confirmation de suppression, explicite si le tag est utilisé.
private struct TagDeletionDialog: ViewModifier {
    @Environment(BudgetStore.self) private var store
    @Binding var item: Tag?
    var onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { item != nil }, set: { if !$0 { item = nil } }),
            titleVisibility: .visible,
            presenting: item
        ) { tag in
            Button("Supprimer", role: .destructive) {
                store.deleteTag(tag)
                onDeleted()
            }
            Button("Annuler", role: .cancel) {}
        } message: { tag in
            let usage = store.usageCount(of: tag)
            if usage > 0 {
                Text("« \(tag.name) » est utilisé par \(usage) \(usage == 1 ? "opération" : "opérations") : il sera retiré de \(usage == 1 ? "cette opération, qui est conservée" : "ces opérations, qui sont conservées").")
            }
        }
    }

    private var title: String {
        guard let item else { return "" }
        return "Supprimer « \(item.name) » ?"
    }
}

private extension View {
    func tagDeletionDialog(item: Binding<Tag?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(TagDeletionDialog(item: item, onDeleted: onDeleted))
    }
}

/// Brouillon de tag en cours d'édition.
struct SettingsTagDraft: Identifiable {
    let id = UUID()
    var tag: Tag
    let isNew: Bool

    init() {
        tag = Tag(name: "", colorIndex: 0)
        isNew = true
    }

    init(tag: Tag) {
        self.tag = tag
        isNew = false
    }
}

private struct SettingsTagSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var draft: SettingsTagDraft
    @State private var pendingDelete: Tag?

    private var canSave: Bool { !draft.tag.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: theme.spacing) {
                        Circle().fill(theme.color(for: draft.tag)).frame(width: 16, height: 16)
                        TextField("Nom", text: $draft.tag.name)
                    }
                }
                Section("Couleur") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 8)], spacing: 8) {
                        ForEach(Array(theme.categoryPalette.enumerated()), id: \.offset) { index, color in
                            Button { draft.tag.colorIndex = index } label: {
                                Circle().fill(color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if draft.tag.colorIndex == index {
                                            Image(systemName: "checkmark").font(theme.captionFont.bold())
                                                .foregroundStyle(theme.surface)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !draft.isNew {
                    Section {
                        Button("Supprimer le tag", role: .destructive) { pendingDelete = draft.tag }
                            .foregroundStyle(theme.negative)
                    }
                }
            }
            .formStyle(.grouped)
            .font(theme.bodyFont)
            .tint(theme.accent)
            .tagDeletionDialog(item: $pendingDelete) { dismiss() }
            .navigationTitle(draft.isNew ? "Nouveau tag" : "Modifier le tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        draft.tag.name = draft.tag.name.trimmingCharacters(in: .whitespaces)
                        store.upsertTag(draft.tag)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
