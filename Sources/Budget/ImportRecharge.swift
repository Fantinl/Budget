import Foundation

/// Recharge Izly repérée dans un relevé : devient un virement vers le compte Izly à l'import.
struct ImportRecharge: Hashable {
    var amount: Decimal
    var date: Date
    var note: String
    var izlyAccountID: String

    /// Le libellé contient un mot-clé de recharge (sans tenir compte de la casse ni des accents).
    static func matches(label: String) -> Bool {
        let text = StatementParser.normalize(label)
        return StudentProfile.rechargeKeywords.contains { text.contains(StatementParser.normalize($0)) }
    }
}
