// Lecture minimale d'une archive zip (un classeur .xlsx), sans dépendance : répertoire central + inflate natif
// (`DecompressionStream("deflate-raw")`, disponible dans WebView2/WebKit et Node ≥ 18).

export interface ZipEntry { name: string; method: number; compressedSize: number; size: number; offset: number }

const u16 = (v: DataView, o: number) => v.getUint16(o, true);
const u32 = (v: DataView, o: number) => v.getUint32(o, true);

export class ZipArchive {
  private readonly view: DataView;
  readonly entries = new Map<string, ZipEntry>();

  constructor(private readonly bytes: Uint8Array) {
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    this.readDirectory();
  }

  private readDirectory() {
    const v = this.view;
    // Fin du répertoire central : signature 0x06054B50, dans les 64 Ko + 22 derniers octets.
    let eocd = -1;
    for (let i = this.bytes.length - 22; i >= Math.max(0, this.bytes.length - 22 - 65535); i--) {
      if (u32(v, i) === 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) throw new Error("archive zip illisible");
    const count = u16(v, eocd + 10);
    let p = u32(v, eocd + 16);
    for (let n = 0; n < count; n++) {
      if (p + 46 > this.bytes.length || u32(v, p) !== 0x02014b50) throw new Error("répertoire zip corrompu");
      const nameLength = u16(v, p + 28), extraLength = u16(v, p + 30), commentLength = u16(v, p + 32);
      const name = new TextDecoder().decode(this.bytes.subarray(p + 46, p + 46 + nameLength));
      this.entries.set(name, { name, method: u16(v, p + 10), compressedSize: u32(v, p + 20), size: u32(v, p + 24), offset: u32(v, p + 42) });
      p += 46 + nameLength + extraLength + commentLength;
    }
  }

  has(name: string) { return this.entries.has(name); }

  /// Contenu décompressé d'un fichier de l'archive, null s'il n'y est pas.
  async read(name: string): Promise<Uint8Array | null> {
    const e = this.entries.get(name);
    if (!e) return null;
    const v = this.view;
    if (e.offset + 30 > this.bytes.length || u32(v, e.offset) !== 0x04034b50) throw new Error("entrée zip corrompue");
    const start = e.offset + 30 + u16(v, e.offset + 26) + u16(v, e.offset + 28);
    const raw = this.bytes.subarray(start, start + e.compressedSize);
    if (e.method === 0) return raw;
    if (e.method !== 8) throw new Error("méthode de compression zip non prise en charge");
    return inflateRaw(raw);
  }

  async readText(name: string): Promise<string | null> {
    const data = await this.read(name);
    return data ? new TextDecoder("utf-8").decode(data) : null;
  }
}

async function inflateRaw(data: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([data as BlobPart]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
