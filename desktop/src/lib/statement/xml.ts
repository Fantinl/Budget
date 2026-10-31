// Lecteur XML événementiel minimal (équivalent de `XMLParser` de Foundation), sans DOMParser :
// il fonctionne aussi dans les tests Node. Suffisant pour les fichiers d'un classeur .xlsx.

export interface XMLHandler {
  start?(name: string, attributes: Record<string, string>): void;
  end?(name: string): void;
  text?(text: string): void;
}

const NAMED: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'" };

export function decodeXMLEntities(s: string): string {
  if (!s.includes("&")) return s;
  return s.replace(/&(#[xX][0-9A-Fa-f]+|#\d+|[A-Za-z]+);/g, (whole, body: string) => {
    if (body[0] === "#") {
      const code = body[1] === "x" || body[1] === "X" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      try { return String.fromCodePoint(code); } catch { return whole; }
    }
    return NAMED[body] ?? whole;
  });
}

/// Nom sans préfixe d'espace de noms (« x:row » → « row »).
const local = (name: string) => name.slice(name.indexOf(":") + 1);

export function parseXML(xml: string, handler: XMLHandler): void {
  const tag = /<!--[\s\S]*?-->|<!\[CDATA\[([\s\S]*?)\]\]>|<\?[\s\S]*?\?>|<!(?:[^>"']|"[^"]*"|'[^']*')*>|<(\/?)([^\s/>]+)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g;
  let last = 0;
  for (let m = tag.exec(xml); m; m = tag.exec(xml)) {
    if (m.index > last) handler.text?.(decodeXMLEntities(xml.slice(last, m.index)));
    last = tag.lastIndex;
    if (m[1] !== undefined) { handler.text?.(m[1]); continue; }   // CDATA
    const name = m[3];
    if (name === undefined) continue;   // commentaire, instruction, déclaration
    if (m[2] === "/") { handler.end?.(local(name)); continue; }
    const attributes: Record<string, string> = {};
    for (const a of m[4].matchAll(/([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) attributes[a[1]] = decodeXMLEntities(a[2] ?? a[3] ?? "");
    handler.start?.(local(name), attributes);
    if (m[5] === "/") handler.end?.(local(name));
  }
  if (last < xml.length) handler.text?.(decodeXMLEntities(xml.slice(last)));
}
