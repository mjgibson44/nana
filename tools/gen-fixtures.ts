/**
 * Golden-fixture generator for the Swift port of the game core.
 *
 * Runs the CANONICAL TypeScript implementation and records its outputs as
 * JSON vectors that the Swift package's parity tests replay bit-for-bit.
 * If the TS core and the fixtures drift, CI fails; if the Swift port and the
 * fixtures disagree, the port is wrong.
 *
 * Run with:  npm run gen:fixtures   (vite-node, so `?raw` imports work)
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { COMMON_WORDS } from '../src/game/commonWords';
import { createTileStream } from '../src/game/battle';
import { extendPuzzle, generatePuzzle } from '../src/game/generator';
import { boardBounds } from '../src/game/levels';
import { seededRng } from '../src/game/rng';
import {
  battleAttackTiles,
  battleDripTilesAt,
  battleRoundAt,
  endlessDripSeconds,
  endlessDripTiles,
  endlessInitialSeconds,
  splitAttackTiles,
} from '../src/game/modes';

const OUT_DIR = join(
  dirname(fileURLToPath(import.meta.url)),
  '../apple/Packages/WordCore/Tests/WordCoreTests/Fixtures',
);
mkdirSync(OUT_DIR, { recursive: true });

const write = (name: string, data: unknown) => {
  writeFileSync(join(OUT_DIR, name), JSON.stringify(data, null, 1) + '\n');
  console.log('wrote', name);
};

/* ------------------------------- rng vectors ------------------------------ */

// The corpus deliberately includes non-ASCII strings: xmur3 hashes UTF-16
// code units, and these pin that (é precomposed vs decomposed, surrogate
// pairs). Real seeds are ASCII, but the port must not silently diverge.
const RNG_SEEDS = [
  '',
  'a',
  'abc123def456',
  '7f3k2m9q1x5z',
  '7f3k2m9q1x5z/attacks/p-a1b2c3d4e5f6-x9y8z7w6v5u4',
  'daily/2026-08-18',
  'é', // é precomposed
  'é', // é decomposed
  '\u{1F004}\u{1F3B2}', // surrogate pairs
  'the quick brown fox jumps over the lazy dog, twice over, for length',
];

write(
  'rng.json',
  RNG_SEEDS.map((seed) => {
    const rng = seededRng(seed);
    const first: number[] = [];
    for (let i = 0; i < 1000; i++) {
      // rng() is u32 / 2^32 with an exact float representation; recover the
      // raw 32-bit value so the fixture compares integers, not floats.
      first.push(rng() * 4294967296);
    }
    return { seed, first };
  }),
);

/* ------------------------------ tile streams ------------------------------ */

// Distinct request patterns get FRESH streams from the same seed. The first
// request sizes the opening deal (identical only when clients ask alike);
// everything after is fixed 5-tile chunks, so differently-sized later
// requests must drain the identical letter sequence.
const STREAM_SEEDS = ['7f3k2m9q1x5z', 'a1b2c3d4e5f6', 'zzzzzzzzzzzz', 'daily/2026-08-18'];
const PATTERNS: number[][] = [
  [15, 1, 2, 5, 1, 10, 3, 7], // battle opening + attack-sized dribbles
  [15, 5, 8, 5, 10, 8], // battle opening + interleaved drips
  [20, 5, 5, 8, 10], // endless-sized opening
  [3, 5, 1, 1, 12], // tiny opening (below STREAM_CHUNK)
  [1, 4, 9, 25], // one-tile opening
];

write(
  'stream.json',
  STREAM_SEEDS.flatMap((seed) =>
    PATTERNS.map((pattern) => {
      const stream = createTileStream(seed);
      return { seed, pattern, batches: pattern.map((n) => stream.next(n)) };
    }),
  ),
);

/* ------------------------------- generator -------------------------------- */

const puzzleCases: object[] = [];
for (const seed of ['gen-a', 'gen-b', 'gen-c']) {
  for (const tileCount of [12, 15, 20, 21, 30]) {
    const rng = seededRng(`${seed}/${tileCount}`);
    const puzzle = generatePuzzle(COMMON_WORDS, tileCount, rng);
    puzzleCases.push({
      seed: `${seed}/${tileCount}`,
      tileCount,
      letters: puzzle.letters,
      // Insertion order matters (the shuffle indexed into Object.values), so
      // carry the solution as ordered entry lists, not a JSON object.
      solutionKeys: puzzle.solution ? Object.keys(puzzle.solution) : null,
      solutionValues: puzzle.solution ? Object.values(puzzle.solution) : null,
      sourceWords: puzzle.sourceWords,
    });
  }
  // Span-capped deals take the 400-attempt path.
  const rng = seededRng(`${seed}/span8`);
  const puzzle = generatePuzzle(COMMON_WORDS, 16, rng, 8);
  puzzleCases.push({
    seed: `${seed}/span8`,
    tileCount: 16,
    maxSpan: 8,
    letters: puzzle.letters,
    solutionKeys: puzzle.solution ? Object.keys(puzzle.solution) : null,
    solutionValues: puzzle.solution ? Object.values(puzzle.solution) : null,
    sourceWords: puzzle.sourceWords,
  });
}
write('generator.json', puzzleCases);

// Extend chains: one continuing rng across an opening deal and five
// extensions, exactly the stream's mechanics spelled out.
const extendCases: object[] = [];
for (const seed of ['ext-a', 'ext-b']) {
  const rng = seededRng(seed);
  const opening = generatePuzzle(COMMON_WORDS, 20, rng);
  let hidden = opening.solution ?? {};
  const chain: object[] = [];
  for (let i = 0; i < 5; i++) {
    const grown = extendPuzzle(hidden, boardBounds(hidden), COMMON_WORDS, 5, rng);
    if (grown.solution) hidden = grown.solution;
    chain.push({ letters: grown.letters, words: grown.words });
  }
  extendCases.push({
    seed,
    openingLetters: opening.letters,
    chain,
    finalBoardSorted: Object.entries(hidden)
      .map(([k, v]) => [k, v])
      .sort((x, y) => (x[0] < y[0] ? -1 : 1)),
  });
}
write('extend.json', extendCases);

/* --------------------------------- modes ---------------------------------- */

const attack: object[] = [];
for (let len = 1; len <= 12; len++) {
  for (let round = 1; round <= 3; round++) {
    for (const grewFrom of [[], [3], [4], [5], [4, 4], [5, 3]]) {
      attack.push({ len, round, grewFrom, result: battleAttackTiles(len, round, grewFrom) });
    }
  }
}
const split: object[] = [];
for (let count = 0; count <= 12; count++) {
  for (let targets = 1; targets <= 7; targets++) {
    for (let from = 0; from < targets; from++) {
      split.push({ count, targets, from, shares: splitAttackTiles(count, targets, from) });
    }
  }
}
const pacing: object[] = [];
for (const pace of ['regular', 'fast'] as const) {
  for (let interval = 0; interval <= 60; interval++) {
    pacing.push({
      pace,
      interval,
      seconds: endlessDripSeconds(interval, pace),
      tiles: endlessDripTiles(interval, pace),
    });
  }
}
const rounds: object[] = [];
for (const seconds of [0, 1, 179, 180, 181, 359, 360, 361, 9999]) {
  rounds.push({ seconds, round: battleRoundAt(seconds) });
}
const drips: object[] = [];
for (let index = 0; index <= 30; index++) {
  drips.push({ index, tiles: battleDripTilesAt(index) });
}
write('modes.json', {
  attack,
  split,
  pacing,
  rounds,
  drips,
  initialSeconds: { regular: endlessInitialSeconds('regular'), fast: endlessInitialSeconds('fast') },
});

console.log('done');
