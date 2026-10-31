// Aides de dessin pour les graphiques en SVG (pas de bibliothèque de graphiques).

/// Graduations « rondes » couvrant [lo, hi].
export function niceTicks(lo: number, hi: number, count = 5): number[] {
  if (hi === lo) hi = lo + 1;
  const raw = (hi - lo) / (count - 1);
  const pow = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map(m => m * pow).find(s => s >= raw) ?? raw;
  const ticks: number[] = [];
  for (let v = Math.floor(lo / step) * step; v <= Math.ceil(hi / step) * step + step / 1e6; v += step) ticks.push(Math.round(v * 1e6) / 1e6);
  return ticks;
}

/// Courbe lissée passant par les points sans dépasser (interpolation monotone, comme `.monotone` de Swift Charts).
export function monotonePath(pts: { x: number; y: number }[]): string {
  const n = pts.length;
  if (n === 0) return "";
  if (n === 1) return `M${pts[0].x},${pts[0].y}`;
  const dx: number[] = [], m: number[] = [];
  for (let i = 0; i < n - 1; i++) { dx.push(pts[i + 1].x - pts[i].x); m.push((pts[i + 1].y - pts[i].y) / dx[i]); }
  const t: number[] = [m[0]];
  for (let i = 1; i < n - 1; i++) t.push(m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2);
  t.push(m[n - 2]);
  for (let i = 0; i < n - 1; i++) {
    if (m[i] === 0) { t[i] = 0; t[i + 1] = 0; continue; }
    const a = t[i] / m[i], b = t[i + 1] / m[i], s = a * a + b * b;
    if (s > 9) { const k = 3 / Math.sqrt(s); t[i] = k * a * m[i]; t[i + 1] = k * b * m[i]; }
  }
  let d = `M${pts[0].x},${pts[0].y}`;
  for (let i = 0; i < n - 1; i++) {
    const h = dx[i] / 3;
    d += ` C${pts[i].x + h},${pts[i].y + t[i] * h} ${pts[i + 1].x - h},${pts[i + 1].y - t[i + 1] * h} ${pts[i + 1].x},${pts[i + 1].y}`;
  }
  return d;
}

/// Secteur d'anneau (angles en radians, 0 = midi, sens horaire). Les bords sont rentrés de `inset` pixels
/// (à combiner avec un contour arrondi de `2 × inset` pour arrondir les angles).
export function ringSlice(cx: number, cy: number, inner: number, outer: number, a0: number, a1: number, gap: number, inset: number): string | null {
  const r0 = inner + inset;
  const r1 = outer - inset;
  const full = a1 - a0 >= Math.PI * 2 - 1e-6;
  if (full) {
    const c = (r: number) => `M${cx - r},${cy} a${r},${r} 0 1,0 ${2 * r},0 a${r},${r} 0 1,0 ${-2 * r},0`;
    return `${c(r1)} ${c(r0)}`;
  }
  const pad1 = (gap / 2 + inset) / r1;
  const pad0 = (gap / 2 + inset) / r0;
  const s1 = a0 + pad1, e1 = a1 - pad1, s0 = a0 + pad0, e0 = a1 - pad0;
  if (e1 <= s1 || e0 <= s0) return null;
  const pt = (r: number, a: number) => `${cx + r * Math.sin(a)},${cy - r * Math.cos(a)}`;
  const large1 = e1 - s1 > Math.PI ? 1 : 0;
  const large0 = e0 - s0 > Math.PI ? 1 : 0;
  return `M${pt(r1, s1)} A${r1},${r1} 0 ${large1} 1 ${pt(r1, e1)} L${pt(r0, e0)} A${r0},${r0} 0 ${large0} 0 ${pt(r0, s0)} Z`;
}
