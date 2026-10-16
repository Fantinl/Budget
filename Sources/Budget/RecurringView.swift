import SwiftUI

private let frLocale = Locale(identifier: "fr_FR")

private extension Date {
    func frFormatted(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = frLocale
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter.string(from: self)
    }
}

extension RecurringOperation {
    /// « Chaque mois, le 5 » / « Chaque semaine, le lundi » / « Chaque année, le 14 juillet ».
    var scheduleDescription: String {
        switch frequency {
        case .weekly: "\(frequency.label), le \(startDate.frFormatted("EEEE"))"
        case .monthly, .quarterly:
            "\(frequency.label), le \(Calendar.current.component(.day, from: startDate))"
        case .yearly: "\(frequency.label), le \(startDate.frFormatted("d MMMM"))"
        }
    }

    /// Montant ramené au mois (hebdo ×52/12, trimestriel /3, annuel /12).
    var monthlyAmount: Decimal {
        switch frequency {
        case .weekly: amount * 52 / 12
        case .monthly: amount
        case .quarterly: amount / 3
        case .yearly: amount / 12
        }
    }
}

struct RecurringView: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.theme) private var theme

    private struct Target: Identifiable {
        var operation: RecurringOperation
        var isNew: Bool
        var id: UUID { operation.id }
    }

    @State private var target: Target?
    @State private var pendingDelete: RecurringOperation?

    private var upcoming: [(RecurringOperation, Date)] {
        store.recurringOperations
            .compactMap { op in
                guard op.isActive, let next = store.nextOccurrence(of: op) else { return nil }
                return (op, next)
            }
            .sorted { $0.1 < $1.1 }
    }

    private var inactive: [RecurringOperation] {
        store.recurringOperations
            .filter { op in !op.isActive || store.nextOccurrence(of: op) == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func monthlyTotal(_ kind: TransactionKind) -> Decimal {
        upcoming.filter { $0.0.kind == kind }.reduce(0) { $0 + $1.0.monthlyAmount }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: theme.spacing) {
                summary
                if store.recurringOperations.isEmpty {
                    Text("Aucune opération récurrente. Ajoutez un loyer, un salaire, un abonnement…")
                        .font(theme.bodyFont)
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, theme.padding * 2)
                }
                ForEach(upcoming, id: \.0.id) { op, next in
                    row(op, next: next, dimmed: false)
                }
                if !inactive.isEmpty {
                    Text("En pause ou terminées")
                        .font(theme.captionFont)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, theme.spacing)
                    ForEach(inactive) { op in
                        row(op, next: nil, dimmed: true)
                    }
                }
            }
            .padding(theme.padding)
            .padding(.bottom, 64)
        }
        .screenBackground()
        .overlay(alignment: .bottomTrailing) { addButton.padding(theme.padding) }
        .sheet(item: $target) { target in
            RecurringFormView(operation: target.operation, isNew: target.isNew)
        }
        .confirmationDialog(
            "Supprimer cette récurrente ?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let op = pendingDelete { store.deleteRecurring(op) }
                pendingDelete = nil
            }
            Button("Annuler", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Les opérations déjà créées sont conservées.")
        }
    }

    private var summary: some View {
        Card {
            HStack {
                summaryItem("Dépenses / mois", monthlyTotal(.expense), color: theme.textPrimary, sign: "")
                Spacer()
                summaryItem("Revenus / mois", monthlyTotal(.income), color: theme.positive, sign: "+")
            }
        }
    }

    private func summaryItem(_ title: String, _ value: Decimal, color: Color, sign: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(theme.captionFont).foregroundStyle(theme.textSecondary)
            Text("\(sign)\(value.euros)").font(theme.amountFont).foregroundStyle(color)
            Text("estimation").font(theme.captionFont).foregroundStyle(theme.textTertiary)
        }
    }

    private func row(_ op: RecurringOperation, next: Date?, dimmed: Bool) -> some View {
        Button {
            target = Target(operation: op, isNew: false)
        } label: {
            Card {
                HStack(spacing: theme.spacing) {
                    CategoryBadge(category: store.category(id: op.categoryID))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(op.name).font(theme.bodyFont).foregroundStyle(theme.textPrimary).lineLimit(1)
                        Text(op.scheduleDescription).font(theme.captionFont).foregroundStyle(theme.textSecondary)
                        Text(statusText(op, next: next)).font(theme.captionFont).foregroundStyle(theme.textTertiary)
                    }
                    Spacer(minLength: theme.spacing)
                    Text(op.kind == .income ? "+\(op.amount.euros)" : op.amount.euros)
                        .font(theme.amountFont)
                        .foregroundStyle(op.kind == .income ? theme.positive : theme.textPrimary)
                }
                .opacity(dimmed ? 0.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Modifier", systemImage: "pencil") { target = Target(operation: op, isNew: false) }
            Button(op.isActive ? "Mettre en pause" : "Réactiver",
                   systemImage: op.isActive ? "pause.circle" : "play.circle") {
                var updated = op
                updated.isActive.toggle()
                store.upsertRecurring(updated)
            }
            Button("Supprimer", systemImage: "trash", role: .destructive) { pendingDelete = op }
        }
    }

    private func statusText(_ op: RecurringOperation, next: Date?) -> String {
        if let next { return "Prochaine : \(next.frFormatted("d MMM"))" }
        return op.isActive ? "Terminée" : "En pause"
    }

    private var addButton: some View {
        Button {
            let first = store.categories(for: .expense).first?.id ?? ""
            target = Target(operation: RecurringOperation(
                name: "", amount: 0, kind: .expense, categoryID: first, accountID: nil, note: "",
                frequency: .monthly, startDate: .now, endDate: nil, isActive: true, lastGeneratedDate: nil),
                isNew: true)
        } label: {
            Label("Nouvelle", systemImage: "plus")
                .font(theme.titleFont)
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, theme.padding + 4)
                .padding(.vertical, theme.spacing)
                .background(theme.accent, in: .capsule)
                .shadow(color: theme.accent.opacity(0.35), radius: 10, y: 4)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Nouvelle opération récurrente")
    }
}
