import Foundation
import Observation

/// Taux réglementés (Livret A, LDDS, LEP, CEL, Livret Jeune, PEL).
/// La copie embarquée (`RateTable.embedded`) doit rester identique à `rates.json` à la racine du dépôt.
struct RateTable: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var rate: Double
        var since: String
        var verified: Bool?
        var note: String?
    }

    struct PELEntry: Codable, Equatable {
        var from: String
        var rate: Double
        var verified: Bool?
    }

    var version: Int
    var updatedAt: String
    var source: String
    var rates: [String: Entry]
    var pel: [PELEntry]

    static let embedded = RateTable(
        version: 1,
        updatedAt: "2026-10-17",
        source: "Journal officiel (arrêté du 28 juillet 2026)",
        rates: [
            "livretA": Entry(rate: 1.7, since: "2026-08-01", verified: true),
            "ldds": Entry(rate: 1.7, since: "2026-08-01", verified: true),
            "lep": Entry(rate: 2.5, since: "2026-08-01", verified: true),
            "livretJeune": Entry(rate: 1.7, since: "2026-08-01", verified: false),
            "cel": Entry(rate: 1.25, since: "2026-08-01", verified: false),
        ],
        pel: [
            PELEntry(from: "2016-02-01", rate: 1.5, verified: true),
            PELEntry(from: "2016-08-01", rate: 1.0, verified: true),
            PELEntry(from: "2023-01-01", rate: 2.0, verified: false),
            PELEntry(from: "2024-01-01", rate: 2.25, verified: false),
            PELEntry(from: "2025-01-01", rate: 1.75, verified: true),
            PELEntry(from: "2026-01-01", rate: 2.0, verified: true),
        ]
    )

    /// Date « yyyy-MM-dd » (fuseau de Paris).
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Paris")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    var updatedDate: Date? { Self.date(updatedAt) }
}

/// Taux réglementé retenu pour un compte.
struct RegulatedRate {
    var rate: Decimal
    var since: Date?
    /// Plancher (Livret Jeune) : la banque peut faire mieux.
    var isMinimum: Bool
}

/// Charge, met en cache et rafraîchit les taux publiés. Seul un GET est envoyé : aucune donnée personnelle.
@MainActor @Observable
final class RateService {
    static let shared = RateService()
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/Fantinl/Budget/main/rates.json")!
    private static let lastCheckKey = "rates.lastCheck"
    private static let refreshInterval: TimeInterval = 7 * 86_400

    private(set) var table = RateTable.embedded
    /// Dernière vérification réussie auprès du serveur.
    private(set) var lastChecked: Date?
    private var cacheLoaded = false

    private init() {
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    // MARK: Lecture

    func regulatedRate(kind: AccountKind, openingDate: Date?) -> RegulatedRate? {
        func decimal(_ value: Double) -> Decimal { Decimal(string: String(value)) ?? Decimal(value) }
        switch kind {
        case .livretA, .ldds, .lep, .livretJeune, .cel:
            guard let entry = table.rates[kind.rawValue] else { return nil }
            return RegulatedRate(rate: decimal(entry.rate), since: RateTable.date(entry.since),
                                 isMinimum: kind == .livretJeune)
        case .pel:
            guard let openingDate else { return nil }
            let match = table.pel
                .compactMap { entry in RateTable.date(entry.from).map { ($0, entry) } }
                .filter { $0.0 <= openingDate }
                .max { $0.0 < $1.0 }
            guard let match else { return nil }
            return RegulatedRate(rate: decimal(match.1.rate), since: match.0, isMinimum: false)
        default:
            return nil
        }
    }

    // MARK: Rafraîchissement

    /// À appeler au lancement : relit le cache, puis télécharge si la dernière vérification a plus de 7 jours.
    func refreshIfNeeded(directory: URL, force: Bool = false) async {
        loadCache(directory: directory)
        if !force, let lastChecked, Date.now.timeIntervalSince(lastChecked) < Self.refreshInterval { return }
        var request = URLRequest(url: Self.remoteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpMethod = "GET"
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let remote = try? JSONDecoder().decode(RateTable.self, from: data) else { return }
        // On ne garde que des taux plus récents ou égaux à ceux déjà connus.
        if remote.updatedAt >= table.updatedAt {
            table = remote
            try? data.write(to: directory.appending(path: "rates.json"), options: .atomic)
        }
        lastChecked = .now
        UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckKey)
    }

    private func loadCache(directory: URL) {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let data = try? Data(contentsOf: directory.appending(path: "rates.json")),
              let cached = try? JSONDecoder().decode(RateTable.self, from: data),
              cached.updatedAt > table.updatedAt else { return }
        table = cached
    }
}
