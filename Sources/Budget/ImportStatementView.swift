import SwiftUI
import UniformTypeIdentifiers

/// Importe un relevé bancaire (CSV ou OFX) : choix du fichier, aperçu corrigeable, import en une fois.
struct ImportStatementView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    /// Ligne de l'aperçu, modifiable par l'utilisateur.
    private struct Item: Identifiable {
        let id = UUID()
        var row: StatementRow
        var categoryID: String
        var isSelected: Bool
        var isDuplicate: Bool
    }

    @State private var showImporter = false
    @State private var fileName: String?
    @State private var errorText: String?
    @State private var table: StatementTable?
    @State private var columns = StatementColumns()
    @State private var split = false
    @State private var skipped = 0
    @State private var items: [Item] = []
    @State private var accountID = Account.mainID // remplacé par le compte par défaut à l'ouverture
    @State private var hasContent = false

    /// Fichier déjà choisi (glisser-déposer) : saute l'étape de sélection.
    private let initialURL: URL?

    init(initialURL: URL? = nil) { self.initialURL = initialURL }

    private var activeAccounts: [Account] { store.accounts.filter { !$0.isArchived } }
    private var duplicateCount: Int { items.filter(\.isDuplicate).count }
    private var selectedCount: Int { items.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            Group {
                if hasContent { previewStep } else { pickStep }
            }
            .screenBackground()
            .tint(theme.accent)
            .navigationTitle("Importer un relevé")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedCount == 0 ? "Importer" : "Importer \(selectedCount) opération\(selectedCount > 1 ? "s" : "")", action: runImport)
                        .disabled(selectedCount == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #endif
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.contentTypes) { result in
            load(result)
        }
        .onAppear {
            accountID = store.defaultAccount.id
            if !activeAccounts.contains(where: { $0.id == accountID }), let first = activeAccounts.first {
                accountID = first.id
            }
            if let initialURL, !hasContent { load(.success(initialURL)) }
        }
    }

    // MARK: Étape 1 : choix du fichier

    private var pickStep: some View {
        VStack(spacing: theme.padding) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: theme.iconSize, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("Exporte le relevé en CSV depuis le site de ta banque, puis choisis le fichier ici.")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Choisir un fichier…") { showImporter = true }
                .buttonStyle(.borderedProminent)
                .font(theme.bodyFont)
            if let errorText {
                Text(errorText)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.negative)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(theme.padding * 2)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Étape 2 : aperçu

    private var previewStep: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing) {
                Card {
                    VStack(alignment: .leading, spacing: theme.spacing) {
                        if let fileName {
                            Label(fileName, systemImage: "doc.text")
                                .font(theme.captionFont)
                                .foregroundStyle(theme.textSecondary)
                        }
                        accountRow
                        if table != nil { columnsPicker }
                        Text(summary)
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                        Button("Choisir un autre fichier…") { showImporter = true }
                            .font(theme.captionFont)
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.accent)
                    }
                }

                if items.isEmpty {
                    Text("Aucune opération lisible avec ces colonnes.")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textSecondary)
                        .padding(theme.padding)
                } else {
                    Card(padded: false) {
                        LazyVStack(spacing: 0) {
                            ForEach($items) { $item in
                                itemRow($item)
                                if item.id != items.last?.id { Divider().overlay(theme.separator) }
                            }
                        }
                    }
                }
            }
            .padding(theme.padding)
        }
    }

    private var summary: String {
        var parts = ["\(items.count) opération\(items.count > 1 ? "s" : "")"]
        if duplicateCount > 0 { parts.append("\(duplicateCount) déjà présente\(duplicateCount > 1 ? "s" : "")") }
        if skipped > 0 { parts.append("\(skipped) ligne\(skipped > 1 ? "s" : "") ignorée\(skipped > 1 ? "s" : "")") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var accountRow: some View {
        HStack {
            Text("Compte")
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            if activeAccounts.count > 1 {
                Picker("Compte", selection: $accountID) {
                    ForEach(activeAccounts) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: accountID) { _, _ in refreshDuplicates() }
            } else {
                Text(activeAccounts.first?.name ?? Account.main.name)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    // Choix des colonnes (CSV uniquement).
    private var columnsPicker: some View {
        let headers = table?.headers ?? []
        return VStack(alignment: .leading, spacing: theme.spacing / 2) {
            Divider().overlay(theme.separator)
            columnMenu("Date", headers: headers, selection: $columns.date, optional: false)
            columnMenu("Libellé", headers: headers, selection: $columns.label, optional: true)
            Picker("Montant", selection: $split) {
                Text("Montant unique").tag(false)
                Text("Débit et crédit").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if split {
                columnMenu("Débit", headers: headers, selection: $columns.debit, optional: true)
                columnMenu("Crédit", headers: headers, selection: $columns.credit, optional: true)
            } else {
                columnMenu("Montant", headers: headers, selection: $columns.amount, optional: false)
            }
        }
        .onChange(of: columns) { _, _ in rebuildItems() }
        .onChange(of: split) { _, _ in rebuildItems() }
    }

    private func columnMenu(_ title: String, headers: [String], selection: Binding<Int?>, optional: Bool) -> some View {
        HStack {
            Text(title)
                .font(theme.bodyFont)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Picker(title, selection: selection) {
                if optional || selection.wrappedValue == nil { Text("Aucune").tag(Int?.none) }
                ForEach(headers.indices, id: \.self) { index in
                    Text(headers[index].isEmpty ? "Colonne \(index + 1)" : headers[index]).tag(Int?.some(index))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private func itemRow(_ item: Binding<Item>) -> some View {
        let value = item.wrappedValue
        let kind = value.row.kind
        return HStack(spacing: theme.spacing) {
            Button {
                item.wrappedValue.isSelected.toggle()
            } label: {
                Image(systemName: value.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(theme.titleFont)
                    .foregroundStyle(value.isSelected ? theme.accent : theme.textTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(value.row.label)
                    .font(theme.bodyFont)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: theme.spacing / 2) {
                    Text(value.row.date.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                    if value.isDuplicate {
                        Text("déjà présente")
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, theme.spacing / 2)
                            .background(theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: theme.smallCornerRadius))
                    }
                }
            }
            Spacer(minLength: theme.spacing)

            Menu {
                Picker("Catégorie", selection: item.categoryID) {
                    ForEach(store.categories(for: kind)) { category in
                        Label(category.label, systemImage: category.icon).tag(category.id)
                    }
                }
            } label: {
                CategoryBadge(category: store.category(id: value.categoryID), size: theme.iconSize * 0.8)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Text(value.row.signedAmount.euros)
                .font(theme.amountFont)
                .foregroundStyle(kind == .income ? theme.positive : theme.textPrimary)
                .frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, theme.padding)
        .padding(.vertical, theme.spacing)
        .opacity(value.isSelected ? 1 : 0.55)
    }

    // MARK: Logique

    private static var contentTypes: [UTType] {
        [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
            + ["ofx", "qfx", "csv"].compactMap { UTType(filenameExtension: $0) }
    }

    private func load(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let content = try StatementParser.parse(data: data)
            fileName = url.lastPathComponent
            errorText = nil
            switch content {
            case .table(let parsed):
                table = parsed
                columns = parsed.columns
                split = parsed.columns.isSplit
                hasContent = true
                rebuildItems()
            case .rows(let parsed):
                table = nil
                skipped = parsed.skipped
                hasContent = true
                items = makeItems(parsed.rows)
            }
        } catch {
            errorText = (error as? StatementError)?.errorDescription ?? "Impossible de lire ce fichier."
        }
    }

    private func rebuildItems() {
        guard let table else { return }
        var used = columns
        if split { used.amount = nil } else { used.debit = nil; used.credit = nil }
        let parsed = StatementParser.rows(from: table, columns: used)
        skipped = parsed.skipped
        items = makeItems(parsed.rows)
    }

    private func makeItems(_ rows: [StatementRow]) -> [Item] {
        let categorizer = StatementCategorizer(categories: store.categories, transactions: store.transactions)
        var index = store.duplicateIndex()
        return rows.map { row in
            let duplicate = consumeDuplicate(row, &index)
            return Item(row: row,
                        categoryID: categorizer.suggest(label: row.label, kind: row.kind),
                        isSelected: !duplicate, isDuplicate: duplicate)
        }
    }

    private func refreshDuplicates() {
        var index = store.duplicateIndex()
        for i in items.indices {
            let duplicate = consumeDuplicate(items[i].row, &index)
            items[i].isDuplicate = duplicate
            items[i].isSelected = !duplicate
        }
    }

    /// Même jour, type, montant et compte (chaque opération existante ne compte qu'une fois), ou même libellé le même jour.
    private func consumeDuplicate(_ row: StatementRow, _ index: inout (amounts: [String: Int], labels: Set<String>)) -> Bool {
        let key = BudgetStore.duplicateKey(date: row.date, kind: row.kind, amount: row.amount, accountID: accountID)
        if let count = index.amounts[key], count > 0 {
            index.amounts[key] = count - 1
            return true
        }
        return index.labels.contains(BudgetStore.duplicateLabelKey(date: row.date, label: row.label, accountID: accountID))
    }

    private func runImport() {
        let target: String? = accountID == Account.mainID ? nil : accountID
        let imported = items.filter(\.isSelected).map { item in
            Transaction(amount: item.row.amount, kind: item.row.kind, categoryID: item.categoryID,
                        note: item.row.label, date: item.row.date, accountID: target)
        }
        store.addImported(imported)
        dismiss()
    }
}
