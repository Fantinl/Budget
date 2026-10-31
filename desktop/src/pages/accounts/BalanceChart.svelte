<script lang="ts">
  // Courbe d'évolution du solde (Chart de AccountDetailView.swift) : aire + ligne lissée, un point par mois.
  import { roundEuros, monthAbbrev } from "../../lib/format";

  let { points, tint }: { points: { date: Date; value: number }[]; tint: string } = $props();

  const height = 160;
  const right = 58;
  const bottom = 20;
  const top = 6;
  let width = $state(600);

  const plotW = $derived(Math.max(width - right, 10));
  const plotH = height - bottom - top;

  const domain = $derived.by(() => {
    const values = points.map(p => p.value);
    let lo = Math.min(0, ...values);
    let hi = Math.max(0, ...values);
    if (hi === lo) hi = lo + 10000;
    return { lo, hi };
  });
  const x = (i: number) => (points.length <= 1 ? plotW / 2 : (i / (points.length - 1)) * plotW);
  const y = (v: number) => top + plotH - ((v - domain.lo) / (domain.hi - domain.lo)) * plotH;

  /// Courbe monotone (interpolation de Fritsch-Carlson), comme `.interpolationMethod(.monotone)`.
  const linePath = $derived.by(() => {
    const n = points.length;
    if (n === 0) return "";
    const xs = points.map((_, i) => x(i));
    const ys = points.map(p => y(p.value));
    if (n === 1) return `M${xs[0]},${ys[0]}`;
    const dx = xs.slice(1).map((v, i) => v - xs[i]);
    const slope = ys.slice(1).map((v, i) => (v - ys[i]) / dx[i]);
    const m = new Array<number>(n);
    m[0] = slope[0];
    m[n - 1] = slope[n - 2];
    for (let i = 1; i < n - 1; i++) m[i] = slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2;
    for (let i = 0; i < n - 1; i++) {
      if (slope[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
      const a = m[i] / slope[i], b = m[i + 1] / slope[i], s = a * a + b * b;
      if (s > 9) { const t = 3 / Math.sqrt(s); m[i] = t * a * slope[i]; m[i + 1] = t * b * slope[i]; }
    }
    let d = `M${xs[0]},${ys[0]}`;
    for (let i = 0; i < n - 1; i++) {
      d += ` C${xs[i] + dx[i] / 3},${ys[i] + (m[i] * dx[i]) / 3} ${xs[i + 1] - dx[i] / 3},${ys[i + 1] - (m[i + 1] * dx[i]) / 3} ${xs[i + 1]},${ys[i + 1]}`;
    }
    return d;
  });
  const areaPath = $derived(points.length > 1 ? `${linePath} L${x(points.length - 1)},${y(0)} L${x(0)},${y(0)} Z` : "");

  const ticks = $derived([0, 1, 2, 3].map(i => domain.lo + ((domain.hi - domain.lo) * i) / 3));
</script>

<div class="chart" bind:clientWidth={width}>
  <svg {width} {height} role="img" aria-label="Évolution du solde sur douze mois">
    {#each ticks as tick (tick)}
      <line x1="0" x2={plotW} y1={y(tick)} y2={y(tick)} stroke="var(--separator)" stroke-width="1" />
      <text x={plotW + 6} y={y(tick) + 4} class="axis">{roundEuros(tick)}</text>
    {/each}
    <path d={areaPath} fill={tint} fill-opacity="0.15" />
    <path d={linePath} fill="none" stroke={tint} stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
    {#each points as p, i (i)}
      {#if i % 2 === 0}<text x={x(i)} y={height - 4} text-anchor="middle" class="axis">{monthAbbrev(p.date)}</text>{/if}
    {/each}
  </svg>
</div>

<style>
  .chart { width: 100%; min-width: 0; }
  svg { display: block; overflow: visible; }
  .axis { fill: var(--text-secondary); font-size: var(--caption); }
</style>
