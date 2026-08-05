import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  DEFAULT_BLITZ,
  DEFAULT_PUZZLE,
  loadBlitzSetup,
  loadPuzzleSetup,
  saveBlitzSetup,
  savePuzzleSetup,
} from '../setups';

/**
 * The tests run in node, so there's no window to read from — and blocked
 * storage is a case worth reaching anyway. `store` is the fake's contents,
 * and setting it to null makes every call throw, the way a locked-down
 * browser does.
 */
let store: Map<string, string> | null = null;

function fakeStorage() {
  return {
    getItem(key: string): string | null {
      if (store === null) throw new Error('storage blocked');
      return store.get(key) ?? null;
    },
    setItem(key: string, value: string): void {
      if (store === null) throw new Error('storage blocked');
      store.set(key, value);
    },
  };
}

beforeEach(() => {
  store = new Map();
  (globalThis as { window?: unknown }).window = { localStorage: fakeStorage() };
});

afterEach(() => {
  delete (globalThis as { window?: unknown }).window;
});

describe('defaults', () => {
  it('opens Puzzle on Flow, flexible tiles and the middle board', () => {
    expect(DEFAULT_PUZZLE).toEqual({ variant: 'flow', lock: 'flexible', size: 13 });
  });

  it('are what a player with nothing stored gets', () => {
    expect(loadPuzzleSetup()).toEqual(DEFAULT_PUZZLE);
    expect(loadBlitzSetup()).toEqual(DEFAULT_BLITZ);
  });
});

describe('round trip', () => {
  it('gives a saved Puzzle setup back', () => {
    savePuzzleSetup({ variant: 'solve', lock: 'locked', size: 19 });
    expect(loadPuzzleSetup()).toEqual({ variant: 'solve', lock: 'locked', size: 19 });
  });

  it('gives a saved Blitz setup back', () => {
    saveBlitzSetup({ pace: 'fast' });
    expect(loadBlitzSetup()).toEqual({ pace: 'fast' });
  });

  it('keeps the last save, not the first', () => {
    savePuzzleSetup({ variant: 'solve', lock: 'locked', size: 9 });
    savePuzzleSetup({ variant: 'flow', lock: 'flexible', size: 19 });
    expect(loadPuzzleSetup().size).toBe(19);
  });
});

describe('untrustworthy storage', () => {
  it('falls back to the defaults for anything that isn’t JSON', () => {
    store?.set('nana.setup.puzzle.v1', 'not json {');
    expect(loadPuzzleSetup()).toEqual(DEFAULT_PUZZLE);
  });

  it('falls back for JSON that isn’t an object', () => {
    store?.set('nana.setup.puzzle.v1', '[1, 2, 3]');
    expect(loadPuzzleSetup()).toEqual(DEFAULT_PUZZLE);
  });

  it('replaces only the fields it can’t use', () => {
    store?.set(
      'nana.setup.puzzle.v1',
      JSON.stringify({ variant: 'solve', lock: 'melted', size: 400 }),
    );
    // The style survives; the two nonsense fields come back as defaults.
    expect(loadPuzzleSetup()).toEqual({
      variant: 'solve',
      lock: DEFAULT_PUZZLE.lock,
      size: DEFAULT_PUZZLE.size,
    });
  });

  it('reads the defaults when storage is blocked outright', () => {
    store = null;
    expect(loadPuzzleSetup()).toEqual(DEFAULT_PUZZLE);
    expect(loadBlitzSetup()).toEqual(DEFAULT_BLITZ);
  });

  it('swallows a write that can’t land', () => {
    store = null;
    expect(() => savePuzzleSetup(DEFAULT_PUZZLE)).not.toThrow();
  });
});
