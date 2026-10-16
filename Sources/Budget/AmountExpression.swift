import SwiftUI

/// Évaluation sûre d'expressions de montant : + − × * ÷ / et parenthèses, virgule ou point décimal.
/// Exemple : « (3×4,20)+2 » donne 14,60. Pas d'`NSExpression` : analyseur récursif maison.
enum AmountExpression {
    /// Résultat arrondi au centime, nil si l'expression est invalide (ou division par zéro).
    static func evaluate(_ text: String) -> Decimal? {
        var parser = Parser(chars: normalize(text))
        guard let value = parser.parseExpression(), parser.atEnd else { return nil }
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded
    }

    /// Montant strictement positif (formulaires), nil sinon.
    static func positiveAmount(_ text: String) -> Decimal? {
        guard let value = evaluate(text), value > 0 else { return nil }
        return value
    }

    /// Le texte contient un vrai calcul (et pas seulement un signe ou un nombre).
    static func containsOperator(_ text: String) -> Bool {
        let chars = normalize(text)
        return chars.dropFirst().contains { "+-*/()".contains($0) } || chars.first == "("
    }

    /// Caractères utiles : espaces et « € » ignorés, symboles typographiques ramenés à l'ASCII.
    private static func normalize(_ text: String) -> [Character] {
        text.compactMap { ch -> Character? in
            switch ch {
            case " ", "\u{00A0}", "\u{202F}", "\t", "€": nil
            case ",": "."
            case "×", "x", "X": "*"
            case "÷": "/"
            case "−", "–": "-"
            default: ch
            }
        }
    }

    private struct Parser {
        let chars: [Character]
        var pos = 0

        init(chars: [Character]) { self.chars = chars }

        var atEnd: Bool { pos >= chars.count }
        private var peek: Character? { pos < chars.count ? chars[pos] : nil }

        // expression = terme (("+" | "-") terme)*
        mutating func parseExpression() -> Decimal? {
            guard var value = parseTerm() else { return nil }
            while let op = peek, op == "+" || op == "-" {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        // terme = facteur (("*" | "/") facteur)*
        private mutating func parseTerm() -> Decimal? {
            guard var value = parseFactor() else { return nil }
            while let op = peek, op == "*" || op == "/" {
                pos += 1
                guard let rhs = parseFactor() else { return nil }
                if op == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                }
            }
            return value
        }

        // facteur = ("+" | "-") facteur | "(" expression ")" | nombre
        private mutating func parseFactor() -> Decimal? {
            guard let ch = peek else { return nil }
            if ch == "-" || ch == "+" {
                pos += 1
                guard let value = parseFactor() else { return nil }
                return ch == "-" ? -value : value
            }
            if ch == "(" {
                pos += 1
                guard let value = parseExpression(), peek == ")" else { return nil }
                pos += 1
                return value
            }
            return parseNumber()
        }

        private mutating func parseNumber() -> Decimal? {
            var digits = ""
            var seenDot = false
            while let ch = peek {
                if ch.isASCII && ch.isNumber {
                    digits.append(ch)
                } else if ch == ".", !seenDot {
                    seenDot = true
                    digits.append(ch)
                } else {
                    break
                }
                pos += 1
            }
            guard digits.contains(where: \.isNumber) else { return nil }
            return Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX"))
        }
    }
}

/// Petit aperçu « = 20,50 € » affiché quand le champ montant contient un calcul.
struct AmountExpressionHint: View {
    @Environment(\.theme) private var theme
    let text: String

    var body: some View {
        if AmountExpression.containsOperator(text) {
            if let value = AmountExpression.evaluate(text) {
                Text("= \(value.euros)")
                    .font(theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text("Calcul invalide")
                    .font(theme.captionFont)
                    .foregroundStyle(theme.negative)
            }
        }
    }
}
