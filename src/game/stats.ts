/**
 * Game history, kept in localStorage so it survives between visits.
 *
 * A game is recorded the moment it finishes — the last level is completed (or
 * skipped past its confirm). Abandoned games are never counted.
 */

export interface GameRecord {
  /** Final score for the game. */
  score: number;
  /** How many words were on the finished board. */
  words: number;
  /** When the game finished, as a Unix timestamp in ms. */
  at: number;
}

export interface Stats {
  /** Every finished game, ever — not capped like `recent`. */
  gamesPlayed: number;
  /** The latest finished games, newest first. */
  recent: GameRecord[];
}

const STORAGE_KEY = 'nana.stats.v1';

/** How many finished games `recent` holds onto. */
const RECENT_LIMIT = 30;

const EMPTY: Stats = { gamesPlayed: 0, recent: [] };

/**
 * Read stats back, trusting nothing: storage can be missing (private
 * browsing), or hold something stale or hand-edited. Anything unusable
 * just means starting from zero.
 */
export function loadStats(): Stats {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return EMPTY;
    const parsed = JSON.parse(raw) as Partial<Stats>;
    const recent = Array.isArray(parsed.recent)
      ? parsed.recent.filter(
          (r): r is GameRecord =>
            typeof r === 'object' &&
            r !== null &&
            typeof r.score === 'number' &&
            typeof r.words === 'number' &&
            typeof r.at === 'number',
        )
      : [];
    const gamesPlayed =
      typeof parsed.gamesPlayed === 'number' && parsed.gamesPlayed >= recent.length
        ? Math.floor(parsed.gamesPlayed)
        : recent.length;
    return { gamesPlayed, recent };
  } catch {
    return EMPTY;
  }
}

/** Add a finished game to the record. Returns the stats as they now stand. */
export function recordGame(score: number, words: number): Stats {
  const stats = loadStats();
  const next: Stats = {
    gamesPlayed: stats.gamesPlayed + 1,
    recent: [{ score, words, at: Date.now() }, ...stats.recent].slice(0, RECENT_LIMIT),
  };
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  } catch {
    // Storage full or blocked — the game still finishes, it just isn't kept.
  }
  return next;
}
