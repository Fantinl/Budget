import SwiftUI
import UniformTypeIdentifiers

/// Période exportable en CSV.
enum CSVPeriod: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, thisYear, all, custom

    var id: Self { self }

    var label: String {
        switch self {
        case .thisMonth: "Ce mois-ci"
        case .lastMonth: "Mois dernier"
        case .thisYear: "Cette année"
        case .all: "Tout"
        case .custom: "Dates personnalisées"
        }
    }

    /// Intervalle [début, fin[ ; nil = sans limite. Pour `.custom`, `to` est inclus.
    func interval(from: Date, to: Date, now: Date = .now) -> DateInterval? {
        let cal = Calendar.current
        switch self {
        case .thisMonth: return cal.dateInterval(of: .month, for: now)
        case .lastMonth: return cal.dateInterval(of: .month, for: now.addingMonths(-1))
        case .thisYear: return cal.dateInterval(of: .year, for: now)
        case .all: return nil
        case .custom:
            let start = cal.startOfDay(for: min(from, to))
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(from, to))) ?? max(from, to)
            return DateInterval(start: start, end: end)
        }
    }

    func fileName(from: Date, to: Date, now: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        switch self {
        case .thisMonth: f.dateFormat = "yyyy-MM"; return "Budget-\(f.string(from: now)).csv"
        case .lastMonth: f.dateFormat = "yyyy-MM"; return "Budget-\(f.string(from: now.addingMonths(-1))).csv"
        case .thisYear: f.dateFormat = "yyyy"; return "Budget-\(f.string(from: now)).csv"
        case .all: return "Budget-tout.csv"
        case .custom:
            f.dateFormat = "yyyy-MM-dd"
            return "Budget-\(f.string(from: min(from, to)))_\(f.string(from: max(from, to))).csv"
        }
    }
}

enum CSVExport {
    /// CSV UTF-8 avec BOM (Excel), séparateur « ; », décimale « , », dates jj/mm/aaaa, dépenses en négatif.
    @MainActor
    static func data(for transactions: [Transaction], store: BudgetStore) -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "fr_FR")
        dateFormatter.dateFormat = "dd/MM/yyyy"
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "fr_FR")
        numberFormatter.usesGroupingSeparator = false
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.decimalSeparator = ","

        var lines = [["Date", "Type", "Catégorie", "Compte", "Description", "Montant"].map(escape).joined(separator: ";")]
        for t in transactions.sorted(by: { $0.date < $1.date }) {
            let amount = numberFormatter.string(from: t.signedAmount as NSDecimalNumber) ?? ""
            // Un virement apparaît comme tel (et non comme dépense/revenu sans catégorie).
            let fields = [dateFormatter.string(from: t.date), t.isTransfer ? "Virement" : t.kind.label,
                          t.isTransfer ? "Virement" : store.category(of: t).label,
                          store.account(id: t.accountID).name, t.note, amount]
            lines.append(fields.map(escape).joined(separator: ";"))
        }
        let text = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    /// Entoure de guillemets si le champ contient « ; », « " » ou un retour à la ligne.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Document à enregistrer via `.fileExporter` (CSV ou JSON de sauvegarde).
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .json]
    static let writableContentTypes: [UTType] = [.commaSeparatedText, .json]

    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
