// Évaluation sûre d'expressions de montant : + − × * ÷ / et parenthèses, virgule ou point décimal.
// Port de AmountExpression.swift. Exemple : « (3×4,20)+2 » donne 14,60 € (1460 centimes).
// Le calcul se fait en fractions exactes (BigInt) : aucun flottant n'intervient dans un montant.

interface Q { n: bigint; d: bigint }

const quotient = (n: bigint, d: bigint): Q => (d < 0n ? { n: -n, d: -d } : { n, d });

/// Caractères utiles : espaces et « € » ignorés, symboles typographiques ramenés à l'ASCII.
function normalize(text: string): string[] {
  const out: string[] = [];
  for (const ch of text) {
    switch (ch) {
      case " ": case " ": case " ": case "\t": case "€": break;
      case ",": out.push("."); break;
      case "×": case "x": case "X": out.push("*"); break;
      case "÷": out.push("/"); break;
      case "−": case "–": out.push("-"); break;
      default: out.push(ch);
    }
  }
  return out;
}

class Parser {
  pos = 0;
  constructor(readonly chars: string[]) {}

  get atEnd() { return this.pos >= this.chars.length; }
  private get peek(): string | undefined { return this.chars[this.pos]; }

  // expression = terme (("+" | "-") terme)*
  parseExpression(): Q | null {
    let value = this.parseTerm();
    if (!value) return null;
    while (this.peek === "+" || this.peek === "-") {
      const op = this.peek;
      this.pos++;
      const rhs = this.parseTerm();
      if (!rhs) return null;
      value = op === "+"
        ? { n: value.n * rhs.d + rhs.n * value.d, d: value.d * rhs.d }
        : { n: value.n * rhs.d - rhs.n * value.d, d: value.d * rhs.d };
    }
    return value;
  }

  // terme = facteur (("*" | "/") facteur)*
  private parseTerm(): Q | null {
    let value = this.parseFactor();
    if (!value) return null;
    while (this.peek === "*" || this.peek === "/") {
      const op = this.peek;
      this.pos++;
      const rhs = this.parseFactor();
      if (!rhs) return null;
      if (op === "*") value = { n: value.n * rhs.n, d: value.d * rhs.d };
      else {
        if (rhs.n === 0n) return null;
        value = quotient(value.n * rhs.d, value.d * rhs.n);
      }
    }
    return value;
  }

  // facteur = ("+" | "-") facteur | "(" expression ")" | nombre
  private parseFactor(): Q | null {
    const ch = this.peek;
    if (ch === undefined) return null;
    if (ch === "-" || ch === "+") {
      this.pos++;
      const value = this.parseFactor();
      if (!value) return null;
      return ch === "-" ? { n: -value.n, d: value.d } : value;
    }
    if (ch === "(") {
      this.pos++;
      const value = this.parseExpression();
      if (!value || this.peek !== ")") return null;
      this.pos++;
      return value;
    }
    return this.parseNumber();
  }

  private parseNumber(): Q | null {
    let digits = "";
    let seenDot = false;
    while (this.peek !== undefined) {
      const ch = this.peek;
      if (ch >= "0" && ch <= "9") digits += ch;
      else if (ch === "." && !seenDot) { seenDot = true; digits += ch; }
      else break;
      this.pos++;
    }
    if (!/\d/.test(digits)) return null;
    const [whole, fraction = ""] = digits.split(".");
    return { n: BigInt(whole + fraction), d: 10n ** BigInt(fraction.length) };
  }
}

/// Résultat en centimes (arrondi au centime, demi vers l'extérieur), null si l'expression est invalide
/// (ou division par zéro).
export function evaluate(text: string): number | null {
  const parser = new Parser(normalize(text));
  const value = parser.parseExpression();
  if (!value || !parser.atEnd) return null;
  const numerator = value.n * 100n;
  const negative = numerator < 0n;
  const abs = negative ? -numerator : numerator;
  const rounded = (2n * abs + value.d) / (2n * value.d);
  return Number(negative ? -rounded : rounded);
}

/// Montant strictement positif en centimes (formulaires), null sinon.
export function positiveAmount(text: string): number | null {
  const value = evaluate(text);
  return value !== null && value > 0 ? value : null;
}

/// Le texte contient un vrai calcul (et pas seulement un signe ou un nombre).
export function containsOperator(text: string): boolean {
  const chars = normalize(text);
  return chars.slice(1).some(c => "+-*/()".includes(c)) || chars[0] === "(";
}
