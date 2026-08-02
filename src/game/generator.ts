import type { Bounds, Direction, TileMap } from './types';
import { asBounds, keyOf } from './types';

/**
 * Puzzle generation.
 *
 * Rather than dealing random letters and hoping they spell something, we
 * build an actual hidden crossword out of common words — each new word
 * crossing an already-placed one, exactly like a finished crossword board —
 * until it uses exactly `tileCount` tiles. The player receives those letters
 * shuffled. This guarantees (by construction) that at least one fully valid,
 * fully connected arrangement of all the letters exists, and because the
 * letters come from several ordinary words there are typically many other
 * arrangements too.
 */

export interface Puzzle {
  /** The dealt letters, shuffled. Length === requested tileCount. */
  letters: string[];
  /** One known-good arrangement (proof of solvability). Null only when the
   * crossword builder fell back to disjoint word sampling. */
  solution: TileMap | null;
  /** The words the letters were drawn from. */
  sourceWords: string[];
}

const MIN_WORD_LEN = 3;
const MAX_WORD_LEN = 8;

function shuffle<T>(items: T[], rng: () => number): T[] {
  const arr = items.slice();
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function pick<T>(items: T[], rng: () => number): T {
  return items[Math.floor(rng() * items.length)];
}

/** Adding a word that crosses one existing tile adds word.length - 1 tiles.
 * The remainder after placing must be 0 (done) or >= MIN_WORD_LEN - 1
 * (still fillable by another crossing word). */
function usableLengths(remaining: number): number[] {
  const lengths: number[] = [];
  for (let len = MIN_WORD_LEN; len <= MAX_WORD_LEN; len++) {
    const rest = remaining - (len - 1);
    if (rest === 0 || rest >= MIN_WORD_LEN - 1) lengths.push(len);
  }
  return lengths;
}

interface BuildState {
  grid: TileMap;
  words: string[];
}

/**
 * Check that `word` can be placed with its `crossIndex`-th letter on the
 * occupied cell (crossRow, crossCol), running in `dir`, without touching or
 * conflicting with anything else. Rejecting all other adjacency means every
 * word on the built grid is exactly one of our chosen words — no accidental
 * side-by-side letter combos to worry about.
 */
function canPlace(
  grid: TileMap,
  word: string,
  crossRow: number,
  crossCol: number,
  crossIndex: number,
  dir: Direction,
): { row: number; col: number } | null {
  const dr = dir === 'down' ? 1 : 0;
  const dc = dir === 'across' ? 1 : 0;
  const startRow = crossRow - dr * crossIndex;
  const startCol = crossCol - dc * crossIndex;

  // Cells immediately before the start and after the end must be empty.
  if (keyOf(startRow - dr, startCol - dc) in grid) return null;
  if (keyOf(startRow + dr * word.length, startCol + dc * word.length) in grid) return null;

  for (let i = 0; i < word.length; i++) {
    const r = startRow + dr * i;
    const c = startCol + dc * i;
    const k = keyOf(r, c);

    if (i === crossIndex) {
      if (grid[k] !== word[i]) return null;
      continue;
    }
    if (k in grid) return null;
    // Lateral neighbors must be empty so we don't butt up against another word.
    if (keyOf(r + dc, c + dr) in grid) return null;
    if (keyOf(r - dc, c - dr) in grid) return null;
  }

  return { row: startRow, col: startCol };
}

function place(state: BuildState, word: string, row: number, col: number, dir: Direction): void {
  const dr = dir === 'down' ? 1 : 0;
  const dc = dir === 'across' ? 1 : 0;
  for (let i = 0; i < word.length; i++) {
    state.grid[keyOf(row + dr * i, col + dc * i)] = word[i];
  }
  state.words.push(word);
}

/** One attempt at growing a crossword to exactly tileCount tiles. */
function tryBuild(
  byLetter: Map<string, string[]>,
  byLength: Map<number, string[]>,
  tileCount: number,
  rng: () => number,
): BuildState | null {
  // Seed word: prefer a mid-length word, but never one that strands an
  // unfillable remainder.
  const seedLengths = usableLengths(tileCount + 1).filter((len) => len <= tileCount);
  if (seedLengths.length === 0) return null;
  const preferred = seedLengths.filter((len) => len >= 5);
  const seedLen = pick(preferred.length > 0 ? preferred : seedLengths, rng);
  const seedPool = byLength.get(seedLen);
  if (!seedPool || seedPool.length === 0) return null;

  const state: BuildState = { grid: {}, words: [] };
  place(state, pick(seedPool, rng), 0, 0, 'across');

  let tiles = Object.keys(state.grid).length;
  let failures = 0;

  while (tiles < tileCount && failures < 500) {
    const lengths = usableLengths(tileCount - tiles);
    if (lengths.length === 0) return null;

    const anchors = Object.keys(state.grid);
    const anchorKey = pick(anchors, rng);
    const comma = anchorKey.indexOf(',');
    const anchorRow = Number(anchorKey.slice(0, comma));
    const anchorCol = Number(anchorKey.slice(comma + 1));
    const anchorLetter = state.grid[anchorKey];

    const candidates = byLetter.get(anchorLetter);
    if (!candidates || candidates.length === 0) {
      failures++;
      continue;
    }

    const word = pick(candidates, rng);
    if (!lengths.includes(word.length)) {
      failures++;
      continue;
    }

    // Random occurrence of the anchor letter within the word.
    const positions: number[] = [];
    for (let i = 0; i < word.length; i++) {
      if (word[i] === anchorLetter) positions.push(i);
    }
    const crossIndex = pick(positions, rng);
    const dir: Direction = rng() < 0.5 ? 'across' : 'down';

    const start = canPlace(state.grid, word, anchorRow, anchorCol, crossIndex, dir);
    if (!start) {
      failures++;
      continue;
    }

    place(state, word, start.row, start.col, dir);
    tiles = Object.keys(state.grid).length;
  }

  return tiles === tileCount ? state : null;
}

/** Normalize a grid so its top-left occupied bound is (0,0). */
function normalize(grid: TileMap): TileMap {
  let minRow = Infinity;
  let minCol = Infinity;
  for (const key of Object.keys(grid)) {
    const comma = key.indexOf(',');
    minRow = Math.min(minRow, Number(key.slice(0, comma)));
    minCol = Math.min(minCol, Number(key.slice(comma + 1)));
  }
  const out: TileMap = {};
  for (const [key, letter] of Object.entries(grid)) {
    const comma = key.indexOf(',');
    out[keyOf(Number(key.slice(0, comma)) - minRow, Number(key.slice(comma + 1)) - minCol)] =
      letter;
  }
  return out;
}

/**
 * Fallback if crossword construction somehow fails: sample disjoint words
 * whose lengths sum to exactly tileCount. The letters still spell real words,
 * we just don't hold a pre-connected arrangement.
 */
function fallbackSample(
  byLength: Map<number, string[]>,
  tileCount: number,
  rng: () => number,
): { letters: string[]; words: string[] } | null {
  for (let attempt = 0; attempt < 200; attempt++) {
    const words: string[] = [];
    let remaining = tileCount;
    let dead = false;
    while (remaining > 0) {
      const lengths: number[] = [];
      for (let len = MIN_WORD_LEN; len <= Math.min(MAX_WORD_LEN, remaining); len++) {
        const rest = remaining - len;
        if ((rest === 0 || rest >= MIN_WORD_LEN) && byLength.has(len)) lengths.push(len);
      }
      if (lengths.length === 0) {
        dead = true;
        break;
      }
      const word = pick(byLength.get(pick(lengths, rng))!, rng);
      words.push(word);
      remaining -= word.length;
    }
    if (!dead) {
      return { letters: words.join('').split(''), words };
    }
  }
  return null;
}

/** Would a word laid from here stay on the board? */
function fitsBoard(
  start: { row: number; col: number },
  length: number,
  dir: Direction,
  bounds: Bounds,
): boolean {
  const endRow = dir === 'down' ? start.row + length - 1 : start.row;
  const endCol = dir === 'across' ? start.col + length - 1 : start.col;
  return (
    start.row >= bounds.minRow &&
    start.col >= bounds.minCol &&
    endRow <= bounds.maxRow &&
    endCol <= bounds.maxCol
  );
}

/**
 * One attempt at growing exactly `tileCount` *new* tiles onto tiles that are
 * already there, every added word crossing something already on the board.
 */
function tryExtend(
  initial: TileMap,
  bounds: Bounds,
  byLetter: Map<string, string[]>,
  tileCount: number,
  rng: () => number,
): BuildState | null {
  const state: BuildState = { grid: { ...initial }, words: [] };
  const before = Object.keys(initial).length;
  let added = 0;
  let failures = 0;

  while (added < tileCount && failures < 800) {
    const lengths = usableLengths(tileCount - added);
    if (lengths.length === 0) return null;

    const anchorKey = pick(Object.keys(state.grid), rng);
    const comma = anchorKey.indexOf(',');
    const anchorRow = Number(anchorKey.slice(0, comma));
    const anchorCol = Number(anchorKey.slice(comma + 1));
    const anchorLetter = state.grid[anchorKey];

    const candidates = byLetter.get(anchorLetter);
    if (!candidates || candidates.length === 0) {
      failures++;
      continue;
    }

    const word = pick(candidates, rng);
    if (!lengths.includes(word.length)) {
      failures++;
      continue;
    }

    const positions: number[] = [];
    for (let i = 0; i < word.length; i++) {
      if (word[i] === anchorLetter) positions.push(i);
    }
    const crossIndex = pick(positions, rng);
    const dir: Direction = rng() < 0.5 ? 'across' : 'down';

    const start = canPlace(state.grid, word, anchorRow, anchorCol, crossIndex, dir);
    if (!start || !fitsBoard(start, word.length, dir, bounds)) {
      failures++;
      continue;
    }

    place(state, word, start.row, start.col, dir);
    added = Object.keys(state.grid).length - before;
  }

  return added === tileCount ? state : null;
}

/**
 * Deal `tileCount` more letters for a board that's already been built on.
 *
 * The letters come from words grown off the tiles already down, so — exactly as
 * for a fresh puzzle — at least one way to play every one of them onto the board
 * as it stands is known to exist by construction. `solution` is that
 * arrangement; it is null only if no extension could be found and the letters
 * fall back to a standalone sample.
 */
export function extendPuzzle(
  board: TileMap,
  size: number | Bounds,
  wordPool: string[],
  tileCount: number,
  rng: () => number = Math.random,
): { letters: string[]; words: string[]; solution: TileMap | null } {
  // Nothing to grow from: this is just a fresh little puzzle of its own.
  if (Object.keys(board).length === 0) {
    const puzzle = generatePuzzle(wordPool, tileCount, rng);
    return { letters: puzzle.letters, words: puzzle.sourceWords, solution: null };
  }

  const byLetter = new Map<string, string[]>();
  for (const word of usableWords(wordPool)) {
    for (const letter of new Set(word)) {
      let bucket = byLetter.get(letter);
      if (!bucket) byLetter.set(letter, (bucket = []));
      bucket.push(word);
    }
  }

  const bounds = asBounds(size);
  for (let attempt = 0; attempt < 200; attempt++) {
    const built = tryExtend(board, bounds, byLetter, tileCount, rng);
    if (!built) continue;
    const letters = Object.keys(built.grid)
      .filter((key) => !(key in board))
      .map((key) => built.grid[key]);
    return { letters: shuffle(letters, rng), words: built.words, solution: built.grid };
  }

  // A board too congested to grow off of. The letters still spell real words;
  // the player just isn't handed a guaranteed home for them.
  const puzzle = generatePuzzle(wordPool, tileCount, rng);
  return { letters: puzzle.letters, words: puzzle.sourceWords, solution: null };
}

function usableWords(wordPool: string[]): string[] {
  return wordPool.filter(
    (w) => w.length >= MIN_WORD_LEN && w.length <= MAX_WORD_LEN && /^[a-z]+$/.test(w),
  );
}

export function generatePuzzle(
  wordPool: string[],
  tileCount = 20,
  rng: () => number = Math.random,
): Puzzle {
  const usable = usableWords(wordPool);
  if (usable.length === 0) throw new Error('word pool is empty');
  if (tileCount < MIN_WORD_LEN) throw new Error(`tileCount must be at least ${MIN_WORD_LEN}`);

  const byLetter = new Map<string, string[]>();
  const byLength = new Map<number, string[]>();
  for (const word of usable) {
    for (const letter of new Set(word)) {
      let bucket = byLetter.get(letter);
      if (!bucket) byLetter.set(letter, (bucket = []));
      bucket.push(word);
    }
    let bucket = byLength.get(word.length);
    if (!bucket) byLength.set(word.length, (bucket = []));
    bucket.push(word);
  }

  for (let attempt = 0; attempt < 100; attempt++) {
    const built = tryBuild(byLetter, byLength, tileCount, rng);
    if (built) {
      const solution = normalize(built.grid);
      return {
        letters: shuffle(Object.values(solution), rng),
        solution,
        sourceWords: built.words,
      };
    }
  }

  const fallback = fallbackSample(byLength, tileCount, rng);
  if (!fallback) throw new Error('could not generate a puzzle from the given word pool');
  return {
    letters: shuffle(fallback.letters, rng),
    solution: null,
    sourceWords: fallback.words,
  };
}
