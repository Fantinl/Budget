import SwiftUI
import UniformTypeIdentifiers

/// Réglages → Données : sauvegardes, export CSV et import de relevé.
struct SettingsDataView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme

    @State private var backups: [BackupInfo] = []
    @State private var restoring: BackupInfo?
    @State private var pendingImport: URL?
    @State private var showImporter = false
    @State private var showStatementImport = false

    @State private var period: CSVPeriod = .thisMonth
    @State private var customFrom = Date.now.startOfMonth
    @State private var customTo = Date.now

    @State private var showExporter = false
    @State private var exportDocument = ExportDocument()
    @State private var exportType: UTType = .commaSeparatedText
    @State private var exportName = ""

    private var fr: Locale { Locale(identifier: "fr_FR") }

    var body: some View {
        Form {
            backupSection
            exportSection
            importSection
        }
        .formStyle(.grouped)
        .listRowBackground(theme.surface)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .font(theme.bodyFont)
        .tint(theme.accent)
        .navigationTitle("Données")
        .onAppear(perform: refresh)
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: exportType,
                      defaultFilename: exportName) { result in
            if case .failure(let error) = result { store.errorMessage = "L'enregistrement a échoué : \(error.localizedDescription)" }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): pendingImport = url
            case .failure(let error): store.errorMessage = "Le fichier n'a pas pu être ouvert : \(error.localizedDescription)"
            }
        }
        .confirmationDialog("Restaurer cette sauvegarde ?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
            Button("Restaurer", role: .destructive) {
                if let backup = restoring { store.restore(backup); refresh() }
                restoring = nil
            }
            Button("Annuler", role: .cancel) { restoring = nil }
        } message: {
            Text("L'état actuel sera sauvegardé avant restauration. Vos opérations et réglages seront remplacés par ceux de la sauvegarde.")
        }
        .confirmationDialog("Remplacer vos données ?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("Importer et remplacer", role: .destructive) {
                if let url = pendingImport { store.importBackup(from: url); refresh() }
                pendingImport = nil
            }
            Button("Annuler", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Les données du fichier remplaceront celles de l'app. L'état actuel sera sauvegardé avant l'import.")
        }
        .sheet(isPresented: $showStatementImport) { ImportStatementView() }
    }

    // MARK: - Sauvegardes

    private var backupSection: some View {
        Section {
            if let last = backups.first {
                LabeledContent("Dernière sauvegarde") {
                    Text(last.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(fr)))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Button {
                store.backupNow()
                refresh()
            } label: {
                Label("Sauvegarder maintenant", systemImage: "externaldrive.badge.plus")
            }
            ForEach(backups) { backup in
                HStack(spacing: theme.spacing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backup.date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(fr)).capitalizedFirst)
                            .font(theme.bodyFont)
                            .foregroundStyle(theme.textPrimary)
                        Text(detail(of: backup))
                            .font(theme.captionFont)
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Button("Restaurer…") { restoring = backup }
                        .buttonStyle(.borderless)
                }
            }
            #if os(macOS)
            Button {
                try? FileManager.default.createDirectory(at: store.backupsDirectory, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([store.backupsDirectory])
            } label: {
                Label("Afficher dans le Finder", systemImage: "folder")
            }
            #endif
            Button {
                prepareExport(try? store.backupFileData(), type: .json, name: store.backupFileName)
            } label: {
                Label("Exporter une sauvegarde…", systemImage: "square.and.arrow.up")
            }
            Button {
                showImporter = true
            } label: {
                Label("Importer une sauvegarde…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Sauvegardes")
        } footer: {
            Text("Une sauvegarde automatique est faite chaque jour. Les 30 plus récentes sont conservées.")
        }
    }

    private func detail(of backup: BackupInfo) -> String {
        var parts: [String] = []
        if let count = backup.transactionCount { parts.append(count <= 1 ? "\(count) opération" : "\(count) opérations") }
        parts.append(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    // MARK: - Export CSV

    private var exportSection: some View {
        Section {
            Picker("Période", selection: $period) {
                ForEach(CSVPeriod.allCases) { Text($0.label).tag($0) }
            }
            if period == .custom {
                DatePicker("Du", selection: $customFrom, displayedComponents: .date)
                DatePicker("Au", selection: $customTo, displayedComponents: .date)
            }
            Button {
                let interval = period.interval(from: customFrom, to: customTo)
                let selected = store.transactions.filter { interval?.contains($0.date) ?? true }
                prepareExport(CSVExport.data(for: selected, store: store), type: .commaSeparatedText,
                              name: period.fileName(from: customFrom, to: customTo))
            } label: {
                Label("Exporter en CSV…", systemImage: "tablecells")
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Fichier compatible Excel : séparateur « ; », montants négatifs pour les dépenses.")
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            Button {
                showStatementImport = true
            } label: {
                Label("Importer un relevé bancaire…", systemImage: "doc.text.magnifyingglass")
            }
        } header: {
            Text("Import")
        }
    }

    // MARK: - Aides

    private func prepareExport(_ data: Data?, type: UTType, name: String) {
        guard let data else {
            store.errorMessage = "Impossible de préparer le fichier."
            return
        }
        exportDocument = ExportDocument(data: data)
        exportType = type
        exportName = name
        showExporter = true
    }

    private func refresh() {
        backups = store.listBackups()
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
