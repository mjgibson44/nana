/**
 * Seeded random numbers.
 *
 * Endless Battle deals every player the same tiles by having each client run
 * the generator itself, from a seed the host shares once at the start of the
 * game. That only works if the same seed always produces the same numbers —
 * which Math.random can't promise — so battles use this little PRNG instead.
 * (Solo games still use Math.random; nothing there needs to be repeatable.)
 */

/** xmur3: hash a string down to a well-mixed 32-bit state. */
function hashString(str: string): number {
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return (h ^= h >>> 16) >>> 0;
}

/**
 * mulberry32: a small, fast PRNG over a 32-bit state. Returns numbers in
 * [0, 1) exactly like Math.random, so it can slot into the generator's
 * injectable `rng` parameter unchanged.
 */
export function seededRng(seed: string): () => number {
  let state = hashString(seed);
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A fresh seed for one battle game. Only the host mints one, so it can lean
 * on Math.random — determinism is only needed downstream of the seed. */
export function randomSeed(): string {
  let seed = '';
  for (let i = 0; i < 12; i++) {
    seed += Math.floor(Math.random() * 36).toString(36);
  }
  return seed;
}
