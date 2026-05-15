import type { MemoryRow } from "@/lib/depthField/types";

export interface Spot { x: number; y: number; z: number }

const X_RANGE: [number, number] = [-0.85, 0.85];
const Y_RANGE: [number, number] = [-0.75, 0.75];
const Z_RANGE: [number, number] = [0.3, 0.8];
const SAMPLE_COUNT = 32;
const FALLBACK_THRESHOLD = 0.2;

// Pick a position for a newly-dropped memory that is as far as possible from
// existing tiles. Sample-based so it's cheap regardless of memory count.
//
// If the field is so dense that no candidate is more than FALLBACK_THRESHOLD
// from its nearest neighbour, we accept the best-of-32 anyway and let the
// natural depth-z separation keep them visually distinct.
export function pickFreeSpot(
  existing: ReadonlyArray<Pick<MemoryRow, "pos_x" | "pos_y">>,
  rng: () => number = Math.random,
): Spot {
  let best: Spot = randomSpot(rng);
  let bestDist = minDistance(best, existing);
  for (let i = 1; i < SAMPLE_COUNT; i++) {
    const cand = randomSpot(rng);
    const d = minDistance(cand, existing);
    if (d > bestDist) { bestDist = d; best = cand; }
  }
  return best;
}

function randomSpot(rng: () => number): Spot {
  return {
    x: lerp(X_RANGE[0], X_RANGE[1], rng()),
    y: lerp(Y_RANGE[0], Y_RANGE[1], rng()),
    z: lerp(Z_RANGE[0], Z_RANGE[1], rng()),
  };
}

function minDistance(s: Spot, existing: ReadonlyArray<Pick<MemoryRow, "pos_x" | "pos_y">>): number {
  if (existing.length === 0) return Infinity;
  let min = Infinity;
  for (const m of existing) {
    const dx = m.pos_x - s.x;
    const dy = m.pos_y - s.y;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d < min) min = d;
  }
  return min;
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export const _internal = { FALLBACK_THRESHOLD, SAMPLE_COUNT };
