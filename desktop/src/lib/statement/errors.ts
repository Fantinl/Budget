export type StatementErrorKind = "unreadable" | "empty" | "legacyExcel" | "excelUnreadable" | "excelUnsupported";

const MESSAGES: Record<StatementErrorKind, string> = {
  unreadable: "Impossible de lire ce fichier.",
  empty: "Aucune opération trouvée dans ce fichier.",
  legacyExcel: "Ce fichier est au format Excel 97-2003 (.xls). Ouvre-le dans Numbers ou Excel et exporte-le en .xlsx ou .csv, puis importe ce fichier.",
  excelUnreadable: "Impossible de lire ce fichier Excel. Exporte-le en .csv depuis Numbers ou Excel, puis importe ce fichier.",
  excelUnsupported: "L'import de fichiers Excel n'est pas disponible sur cet appareil. Exporte le relevé en CSV.",
};

export class StatementError extends Error {
  constructor(readonly kind: StatementErrorKind) { super(MESSAGES[kind]); }
}
