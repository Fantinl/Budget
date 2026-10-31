// Port de StatementParserTests, SpreadsheetTests et ImportIzlyTests.
import { describe, expect, it } from "vitest";
import { type Account, MAIN_ACCOUNT_ID, defaultCategories, newAccount } from "../model";
import { balance } from "../logic/accounts";
import { addImported, duplicateIndex, duplicateKey, duplicateLabelKey, isRechargeLabel, type ImportRecharge } from "../logic/import";
import { toInputDate } from "../dates";
import { day, expense, makeStore, tick } from "../test/support";
import { isTransfer, isSpending } from "../model";
import { StatementCategorizer } from "./categorizer";
import {
  StatementError, type StatementContent, type StatementRow, cleanLabel, detectColumns, isSplit, normalize, parseAmount, parseDate,
  parseStatement, rowAmount, rowKind, rowsFromTable, tokenize,
} from "./parser";
import { dateText, numberText } from "./spreadsheet";

const bytes = (s: string) => new TextEncoder().encode(s);
/// Latin 1 / Windows-1252 : un octet par caractère (les textes de test n'ont que des caractères latins courants).
const latin1 = (s: string) => Uint8Array.from(s, c => c.charCodeAt(0));
const ymd = toInputDate;

async function parseRows(data: Uint8Array) {
  const content: StatementContent = await parseStatement(data);
  if ("table" in content) {
    const result = rowsFromTable(content.table, content.table.columns);
    return { rows: result.rows, skipped: result.skipped, table: content.table };
  }
  return { rows: content.result.rows, skipped: content.result.skipped, table: null };
}
const amounts = (rows: StatementRow[]) => rows.map(r => r.signedCents);

describe("StatementParser: CSV", () => {
  it("débit/crédit en Latin 1 avec préambule", async () => {
    const text = "Compte;12345678901\nSolde;1 234,56\n\nDate;Libellé;Débit euros;Crédit euros;\n15/03/2024;PAIEMENT CB CARREFOUR  MARKET;12,50;;\n16/03/2024;VIREMENT SALAIRE;;1 800,00;\n17/03/24;\"PRLV \"\"FREE\"\" MOBILE\";19,99;;\nTotal;;;;\n";
    const result = await parseRows(latin1(text));
    expect(isSplit(result.table!.columns)).toBe(true);
    expect(result.rows).toHaveLength(3);
    expect(result.rows.map(r => ymd(r.date))).toEqual(["2024-03-15", "2024-03-16", "2024-03-17"]);
    expect(amounts(result.rows)).toEqual([-1250, 180000, -1999]);
    expect(result.rows[0].label).toBe("PAIEMENT CB CARREFOUR MARKET");
    expect(result.rows[2].label).toBe("PRLV \"FREE\" MOBILE");
    expect(rowKind(result.rows[1])).toBe("income");
    expect(result.skipped).toBe(1);   // la ligne « Total » est ignorée
  });

  it("montant signé en Windows-1252", async () => {
    const text = "Date operation;Libelle operation;Montant\n2024-03-01;LOYER MARS;-750,00\n01/03/2024;REMBOURSEMENT CPAM;+23,40\n;;\nfoo;bar;baz\n";
    const result = await parseRows(latin1(text));
    expect(isSplit(result.table!.columns)).toBe(false);
    expect(amounts(result.rows)).toEqual([-75000, 2340]);
    expect(result.rows.map(r => ymd(r.date))).toEqual(["2024-03-01", "2024-03-01"]);
    expect(result.skipped).toBe(1);
  });

  it("décode les accents Windows-1252 (é = 0xE9, € = 0x80)", async () => {
    const data = Uint8Array.from([...latin1("Date;Libell"), 0xe9, ...latin1(";Montant\n15/10/2026;Caf"), 0xe9, ...latin1(";-3,20 "), 0x80, 0x0a]);
    const result = await parseRows(data);
    expect(result.table!.headers[1]).toBe("Libellé");
    expect(result.rows[0].label).toBe("Café");
    expect(result.rows[0].signedCents).toBe(-320);
  });

  it("style Boursorama avec le signe euro", async () => {
    const text = "dateOp;dateVal;label;category;categoryParent;supplierFound;amount;comment;accountNum;accountLabel;accountbalance\n2024-03-05;2024-03-05;\"CB Netflix\";Loisirs;Loisirs;netflix;-13,49 €;;0001;CC;100\n";
    const result = await parseRows(bytes(text));
    expect(result.rows).toHaveLength(1);
    expect(result.rows[0].label).toBe("CB Netflix");
    expect(result.rows[0].signedCents).toBe(-1349);
  });

  it("séparateur virgule et nombres anglais", async () => {
    const text = "Date,Description,Amount\n03/04/2024,\"Coffee, shop\",\"-1,234.50\"\n04/04/2024,Uber,-12.5\n";
    const result = await parseRows(bytes(text));
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0].label).toBe("Coffee, shop");
    expect(amounts(result.rows)).toEqual([-123450, -1250]);
  });

  it("retire la marque UTF-8 (BOM)", async () => {
    const result = await parseRows(Uint8Array.from([0xef, 0xbb, 0xbf, ...bytes("Date;Libellé;Montant\n15/10/2026;Café;-3,20\n")]));
    expect(result.table!.headers[0]).toBe("Date");
    expect(result.rows).toHaveLength(1);
  });

  it("lit l'UTF-16", async () => {
    const text = "Date;Libellé;Montant\n15/10/2026;Café;-3,20\n";
    const data = new Uint8Array(2 + text.length * 2);
    data.set([0xff, 0xfe]);
    for (let i = 0; i < text.length; i++) { data[2 + i * 2] = text.charCodeAt(i) & 0xff; data[3 + i * 2] = text.charCodeAt(i) >> 8; }
    const result = await parseRows(data);
    expect(result.rows[0].label).toBe("Café");
  });

  it("fichiers vides ou illisibles", async () => {
    await expect(parseStatement(new Uint8Array())).rejects.toBeInstanceOf(StatementError);
    // Un CSV sans date ni montant reconnaissables ne produit aucune opération.
    const rows = await parseRows(bytes("a,b,c\n1,2,3\n")).catch(() => null);
    expect(rows?.rows.length ?? 0).toBe(0);
  });
});

describe("StatementParser: OFX", () => {
  it("lit un OFX", async () => {
    const ofx = "OFXHEADER:100\n<OFX><STMTTRN>\n<TRNTYPE>DEBIT\n<DTPOSTED>20240315120000[+1:CET]\n<TRNAMT>-45.30\n<NAME>AUCHAN\n<MEMO>CB 1234\n</STMTTRN></OFX>";
    const result = await parseRows(bytes(ofx));
    expect(result.table).toBeNull();
    expect(result.rows).toHaveLength(1);
    expect(ymd(result.rows[0].date)).toBe("2024-03-15");
    expect(result.rows[0].signedCents).toBe(-4530);
    expect(result.rows[0].label).toContain("AUCHAN");
  });

  it("entités XML et deux opérations", async () => {
    const ofx = "<OFX><STMTTRN><DTPOSTED>20240102<TRNAMT>10.00<NAME>A &amp; B</STMTTRN><STMTTRN><DTPOSTED>20240103<TRNAMT>-2.00<NAME>C</STMTTRN></OFX>";
    const result = await parseRows(bytes(ofx));
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0].label).toContain("A & B");
    expect(rowKind(result.rows[1])).toBe("expense");
  });
});

describe("StatementParser: valeurs", () => {
  it("parseAmount", () => {
    expect(parseAmount("1 234,56 €")).toBe(123456);
    expect(parseAmount("1.234.567")).toBe(123456700);
    expect(parseAmount("12,50-")).toBe(-1250);
    expect(parseAmount("-1,234.50")).toBe(-123450);
    expect(parseAmount("+23,40")).toBe(2340);
    expect(parseAmount("(12,50)")).toBe(-1250);
    expect(parseAmount("12")).toBe(1200);
    expect(parseAmount("abc")).toBeNull();
    expect(parseAmount("")).toBeNull();
  });

  it("parseDate", () => {
    expect(ymd(parseDate("15/03/2024")!)).toBe("2024-03-15");
    expect(ymd(parseDate("15/03/24")!)).toBe("2024-03-15");
    expect(ymd(parseDate("2024-03-15")!)).toBe("2024-03-15");
    expect(ymd(parseDate("15.03.2024")!)).toBe("2024-03-15");
    expect(ymd(parseDate("20240315")!)).toBe("2024-03-15");
    expect(parseDate("pas une date")).toBeNull();
    expect(parseDate("31/02/2024")).toBeNull();
  });

  it("normalize retire accents et casse", () => {
    expect(normalize("Crédit  Agricole")).toBe(normalize("credit agricole"));
  });

  it("cleanLabel réduit les espaces", () => {
    expect(cleanLabel("  CB   CARREFOUR \n MARKET ")).toBe("CB CARREFOUR MARKET");
  });

  it("détection des colonnes", () => {
    const split = detectColumns(["Date", "Libellé", "Débit", "Crédit"]);
    expect([split.date, split.label, split.debit, split.credit, split.amount]).toEqual([0, 1, 2, 3, null]);
    expect(detectColumns(["Date", "Libellé", "Montant"]).amount).toBe(2);
  });

  it("tokenize gère guillemets et retours à la ligne", () => {
    const records = tokenize("a;\"b;c\";d\n\"x\ny\";\"q\"\"r\";z\n", ";");
    expect(records[0]).toEqual(["a", "b;c", "d"]);
    expect(records[1]).toEqual(["x\ny", "q\"r", "z"]);
    expect(tokenize("a;b\r\nc;d\r\n", ";")).toEqual([["a", "b"], ["c", "d"]]);
  });
});

// MARK: - Tableurs

/// CRC-32 d'un fichier (exigé par le format zip, ignoré par notre lecteur mais écrit correctement).
function crc32(data: Uint8Array): number {
  let c, crc = 0xffffffff;
  for (const b of data) { c = (crc ^ b) & 0xff; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crc = (crc >>> 8) ^ c; }
  return (crc ^ 0xffffffff) >>> 0;
}

async function deflateRaw(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data as BlobPart]).stream().pipeThrough(new CompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/// Fabrique une archive zip (fichiers compressés, sauf ceux de `stored`).
async function makeZip(files: Record<string, string>, stored: string[] = []): Promise<Uint8Array> {
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  const header = (size: number) => { const b = new Uint8Array(size); return { b, v: new DataView(b.buffer) }; };
  for (const [name, text] of Object.entries(files)) {
    const raw = bytes(text), nameBytes = bytes(name);
    const method = stored.includes(name) ? 0 : 8;
    const body = method === 0 ? raw : await deflateRaw(raw);
    const crc = crc32(raw);
    const local = header(30 + nameBytes.length);
    local.v.setUint32(0, 0x04034b50, true); local.v.setUint16(4, 20, true); local.v.setUint16(8, method, true);
    local.v.setUint32(14, crc, true); local.v.setUint32(18, body.length, true); local.v.setUint32(22, raw.length, true);
    local.v.setUint16(26, nameBytes.length, true); local.b.set(nameBytes, 30);
    const dir = header(46 + nameBytes.length);
    dir.v.setUint32(0, 0x02014b50, true); dir.v.setUint16(4, 20, true); dir.v.setUint16(6, 20, true); dir.v.setUint16(10, method, true);
    dir.v.setUint32(16, crc, true); dir.v.setUint32(20, body.length, true); dir.v.setUint32(24, raw.length, true);
    dir.v.setUint16(28, nameBytes.length, true); dir.v.setUint32(42, offset, true); dir.b.set(nameBytes, 46);
    parts.push(local.b, body);
    central.push(dir.b);
    offset += local.b.length + body.length;
  }
  const centralSize = central.reduce((n, c) => n + c.length, 0);
  const end = header(22);
  end.v.setUint32(0, 0x06054b50, true); end.v.setUint16(8, central.length, true); end.v.setUint16(10, central.length, true);
  end.v.setUint32(12, centralSize, true); end.v.setUint32(16, offset, true);
  const all = [...parts, ...central, end.b];
  const out = new Uint8Array(all.reduce((n, p) => n + p.length, 0));
  let p = 0;
  for (const part of all) { out.set(part, p); p += part.length; }
  return out;
}

const NS = `xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"`;
const contentTypes = `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>`;
const workbook = `<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Vide" sheetId="1" r:id="rId1"/><sheet name="Releve" sheetId="2" r:id="rId2"/></sheets></workbook>`;
const rels = `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="x" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="x" Target="worksheets/sheet2.xml"/></Relationships>`;
const styles = `<?xml version="1.0"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="dd\\/mm\\/yyyy"/></numFmts><cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/></cellXfs></styleSheet>`;

/// Classeur : première feuille vide, deuxième feuille = `sheet`.
const makeXLSX = (sheet: string, sharedStrings: string, stored: string[] = []) => makeZip({
  "[Content_Types].xml": contentTypes, "xl/workbook.xml": workbook, "xl/_rels/workbook.xml.rels": rels, "xl/styles.xml": styles,
  "xl/worksheets/sheet1.xml": `<worksheet ${NS}><sheetData/></worksheet>`, "xl/worksheets/sheet2.xml": sheet,
  "xl/sharedStrings.xml": sharedStrings,
}, stored);

describe("Spreadsheet", () => {
  it("xlsx débit/crédit avec préambule et dates stylées", async () => {
    const sst = `<sst ${NS}><si><t>Compte courant n°123</t></si><si><t>Solde au 01/10/2026</t></si><si><t>Date</t></si><si><t>Libellé</t></si><si><t>Débit</t></si><si><t>Crédit</t></si><si><r><t>CB </t></r><r><rPr><b/></rPr><t>CARREFOUR</t></r></si><si><t>VIR SALAIRE</t></si></sst>`;
    const sheet = `<worksheet ${NS}><sheetData>
      <row r="1"><c r="A1" t="s"><v>0</v></c></row>
      <row r="2"><c r="A2" t="s"><v>1</v></c></row>
      <row r="4"><c r="A4" t="s"><v>2</v></c><c r="B4" t="s"><v>3</v></c><c r="C4" t="s"><v>4</v></c><c r="D4" t="s"><v>5</v></c></row>
      <row r="5"><c r="A5" s="1"><v>46310</v></c><c r="B5" t="s"><v>6</v></c><c r="C5"><v>12.3</v></c></row>
      <row r="6"><c r="A6" s="2"><v>46311.5</v></c><c r="B6" t="inlineStr"><is><t>PRLV EDF</t></is></c><c r="C6"><v>1.2E2</v></c></row>
      <row r="7"><c r="A7" s="1"><v>46312</v></c><c r="B7" t="s"><v>7</v></c><c r="D7"><v>1234.5600000000002</v></c></row>
      </sheetData></worksheet>`;
    const result = await parseRows(await makeXLSX(sheet, sst));
    expect(result.table!.headers).toEqual(["Date", "Libellé", "Débit", "Crédit"]);
    expect(result.rows).toHaveLength(3);
    expect(result.rows.map(r => ymd(r.date))).toEqual(["2026-10-15", "2026-10-16", "2026-10-17"]);   // 46310 = 15/10/2026
    expect(result.rows.map(r => r.label)).toEqual(["CB CARREFOUR", "PRLV EDF", "VIR SALAIRE"]);
    expect(amounts(result.rows)).toEqual([-1230, -12000, 123456]);
  });

  it("xlsx montant signé, dates en texte et fichiers stockés sans compression", async () => {
    const sst = `<sst ${NS}><si><t>Date</t></si><si><t>Libellé</t></si><si><t>Montant</t></si><si><t>15/10/2026</t></si><si><t>RESTO</t></si></sst>`;
    const sheet = `<worksheet ${NS}><sheetData>
      <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>
      <row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c><c r="C2"><v>-23.9</v></c></row>
      <row r="3"><c r="A3"><v>46310</v></c><c r="B3" t="str"><v>SANS STYLE</v></c><c r="C3"><v>5</v></c></row>
      </sheetData></worksheet>`;
    const result = await parseRows(await makeXLSX(sheet, sst, ["xl/sharedStrings.xml", "xl/worksheets/sheet2.xml"]));
    expect(result.rows).toHaveLength(2);
    expect(result.rows.map(r => ymd(r.date))).toEqual(["2026-10-15", "2026-10-15"]);   // date sans style → nombre de série converti
    expect(amounts(result.rows)).toEqual([-2390, 500]);
    expect(result.rows[1].label).toBe("SANS STYLE");
  });

  it("dates et nombres de série", () => {
    expect(dateText(46310)).toBe("15/10/2026");
    expect(dateText(46311.5)).toBe("16/10/2026");
    expect(numberText("1.2E2")).toBe("120");
    expect(numberText("1234.5600000000002")).toBe("1234.56");
    expect(numberText("2.675")).toBe("2.68");
    expect(numberText("pas un nombre")).toBe("pas un nombre");
  });

  it("un xlsx corrompu lève une erreur", async () => {
    const fake = Uint8Array.from([0x50, 0x4b, 0x03, 0x04, ...new Array(50).fill(0)]);
    await expect(parseStatement(fake)).rejects.toMatchObject({ kind: "excelUnreadable" });
  });

  it("xls exporté en HTML", async () => {
    const html = `<html><body><table><tr><th>Date</th><th>Libell&eacute;</th><th>Montant</th></tr><tr><td>15/10/2026</td><td>CAF&nbsp;ALLOC &amp; co&#233;</td><td>1&nbsp;234,50</td></tr><tr><td>16/10/2026</td><td>Caf&eacute;</td><td>-3,20</td></tr></table></body></html>`;
    const result = await parseRows(bytes(html));
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0].label).toBe("CAF ALLOC & coé");
    expect(result.rows[0].signedCents).toBe(123450);
    expect(result.rows[1].label).toBe("Café");
    expect(result.rows[1].signedCents).toBe(-320);
  });

  it("un xls binaire donne une erreur explicite", async () => {
    const ole = Uint8Array.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, ...new Array(100).fill(0)]);
    await expect(parseStatement(ole)).rejects.toMatchObject({ kind: "legacyExcel" });
  });

  it("le CSV est toujours lu", async () => {
    const csv = "Relevé\nDate;Libellé;Débit;Crédit\n15/10/2026;\"CB \"\"X\"\" ;1\";12,50;\n16/10/2026;SALAIRE;;1 500,00\nfoo;bar;;\n";
    const result = await parseRows(bytes(csv));
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0].label).toBe("CB \"X\" ;1");
    expect(amounts(result.rows)).toEqual([-1250, 150000]);
    expect(result.skipped).toBe(1);
  });
});

// MARK: - Import et Izly

describe("ImportIzly", () => {
  const today = new Date(2026, 9, 12);
  const makeIzly = (): Account => newAccount({ name: "Izly", kind: "izly", colorIndex: 0 });

  async function importSample(s: Awaited<ReturnType<typeof makeStore>>, izly: Account) {
    const rows: StatementRow[] = [
      { date: today, label: "CB IZLY SMONEY 12/10", signedCents: -2000 },
      { date: today, label: "CARREFOUR", signedCents: -3500 },
      { date: today, label: "SALAIRE", signedCents: 150000 },
    ];
    const categorizer = new StatementCategorizer(s.categories, s.transactions);
    const imported = rows.slice(1).map(r => ({
      ...expense(rowAmount(r) / 100, categorizer.suggest(r.label, rowKind(r)), r.date), kind: rowKind(r), note: r.label,
    }));
    const recharge: ImportRecharge = { amountCents: 2000, date: today, note: rows[0].label, izlyAccountID: izly.id };
    addImported(s, imported, [recharge], MAIN_ACCOUNT_ID);
  }

  it("détecte le libellé d'une recharge", () => {
    expect(isRechargeLabel("CB IZLY SMONEY 12/10")).toBe(true);
    expect(isRechargeLabel("recharge izly")).toBe(true);
    expect(isRechargeLabel("CARREFOUR")).toBe(false);
  });

  it("une recharge devient un virement vers Izly", async () => {
    const s = await makeStore();
    const izly = makeIzly();
    s.accounts = [...s.accounts, izly];
    await importSample(s, izly);
    const legs = s.transactions.filter(isTransfer);
    expect(legs).toHaveLength(2);
    expect(legs[0].transferID).toBe(legs[1].transferID);
    expect(s.transactions).toHaveLength(4);
    expect(balance(s, s.account(MAIN_ACCOUNT_ID))).toBe(150000 - 3500 - 2000);
    expect(balance(s, izly)).toBe(2000);
    expect(legs.some(isSpending)).toBe(false);   // une recharge n'est pas une dépense
  });

  it("un réimport est détecté comme doublon", async () => {
    const s = await makeStore();
    const izly = makeIzly();
    s.accounts = [...s.accounts, izly];
    await importSample(s, izly);
    const index = duplicateIndex(s);
    expect(index.amounts.get(duplicateKey(today, "expense", 2000, MAIN_ACCOUNT_ID)) ?? 0).toBeGreaterThan(0);
    expect(index.labels.has(duplicateLabelKey(today, "carrefour", MAIN_ACCOUNT_ID))).toBe(true);
  });

  it("une recharge depuis le compte Izly lui-même est ignorée", async () => {
    const s = await makeStore();
    const izly = makeIzly();
    s.accounts = [...s.accounts, izly];
    addImported(s, [], [{ amountCents: 2000, date: today, note: "IZLY", izlyAccountID: izly.id }], izly.id);
    expect(s.transactions).toEqual([]);
  });

  it("l'import est une seule étape d'annulation", async () => {
    const s = await makeStore();
    const izly = makeIzly();
    s.accounts = [...s.accounts, izly];
    await importSample(s, izly);
    await tick();
    s.undo();
    expect(s.transactions).toEqual([]);
  });

  it("le Crous est classé en restaurant", () => {
    const categorizer = new StatementCategorizer(defaultCategories, []);
    expect(categorizer.suggest("CB CROUS PARIS", "expense")).toBe("restaurants");
  });

  it("un import sans recharge garde le comportement simple", async () => {
    const s = await makeStore();
    addImported(s, [expense(5, "otherExpense", today)]);
    expect(s.transactions).toHaveLength(1);
    addImported(s, []);
    expect(s.transactions).toHaveLength(1);
  });

  it("le catégoriseur apprend des opérations existantes", async () => {
    const s = await makeStore();
    s.transactions = [{ ...expense(10, "leisure", day(2026, 9, 1)), note: "Cinema Pathe Gaumont" }];
    const categorizer = new StatementCategorizer(s.categories, s.transactions);
    expect(categorizer.suggest("CB CINEMA PATHE GAUMONT 14/10", "expense")).toBe("leisure");
    expect(categorizer.suggest("CARREFOUR MARKET", "expense")).toBe("groceries");
    expect(categorizer.suggest("TRUC INCONNU", "expense")).toBe("otherExpense");
    expect(categorizer.suggest("VIREMENT SALAIRE", "income")).toBe("salary");
  });
});
