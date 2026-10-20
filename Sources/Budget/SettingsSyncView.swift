import SwiftUI
import UniformTypeIdentifiers

/// Réglages → Synchronisation : dossier partagé (iCloud Drive) entre le Mac et l'iPhone.
struct SettingsSyncView: View {
    @Environment(SyncCoordinator.self) private var sync: SyncCoordinator?
    @Environment(\.theme) private var theme

    @State private var showPicker = false
    @State private var confirmStop = false

    var body: some View {
        Form {
            if let sync {
                SyncFolderSection(sync: sync, showPicker: $showPicker, confirmStop: $confirmStop)
                if sync.isConfigured { SyncStatusSection(sync: sync) }
            } else {
                Section { Text("La synchronisation n'est pas disponible.").foregroundStyle(theme.textSecondary) }
            }
        }
        .formStyle(.grouped)
        .listRowBackground(theme.surface)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .font(theme.bodyFont)
        .tint(theme.accent)
        .navigationTitle("Synchronisation")
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            handlePicked(result)
        }
        .confirmationDialog("Arrêter la synchronisation ?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Arrêter", role: .destructive) { sync?.stop() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tes données restent sur cet appareil. Le fichier du dossier n'est pas supprimé.")
        }
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        guard let sync, case .success(let url) = result else { return }
        Task { await sync.chooseFolder(url) }
    }
}

/// Explication, dossier actuel et boutons.
private struct SyncFolderSection: View {
    let sync: SyncCoordinator
    @Binding var showPicker: Bool
    @Binding var confirmStop: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        Section {
            if let name = sync.folderName {
                LabeledContent("Dossier") { Text(name).foregroundStyle(theme.textSecondary) }
            }
            Button {
                showPicker = true
            } label: {
                Label("Choisir le dossier…", systemImage: "folder.badge.plus")
            }
            if sync.isConfigured {
                Button(role: .destructive) {
                    confirmStop = true
                } label: {
                    Label("Arrêter la synchronisation", systemImage: "xmark.icloud")
                }
                .foregroundStyle(theme.negative)
            }
        } header: {
            Text("Dossier partagé")
        } footer: {
            Text("Choisis un dossier dans iCloud Drive : le Mac et l'iPhone y partagent tes données.")
        }
    }
}

/// Dernière synchro, erreur, bouton « Synchroniser maintenant ».
private struct SyncStatusSection: View {
    let sync: SyncCoordinator
    @Environment(\.theme) private var theme

    var body: some View {
        Section {
            Button {
                Task { await sync.syncNow() }
            } label: {
                HStack {
                    Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                    if sync.isSyncing {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(sync.isSyncing)
            LabeledContent("Dernière synchro") { lastSyncText }
            if let error = sync.lastError {
                Text(error)
                    .font(theme.captionFont)
                    .foregroundStyle(theme.negative)
            }
        } header: {
            Text("État")
        }
    }

    @ViewBuilder private var lastSyncText: some View {
        if let date = sync.lastSync {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(Self.relative(date)).foregroundStyle(theme.textSecondary)
            }
        } else {
            Text("Jamais").foregroundStyle(theme.textSecondary)
        }
    }

    private static func relative(_ date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 45 { return "à l'instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
