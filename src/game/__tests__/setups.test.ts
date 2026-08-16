import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_SOLO, loadSoloSetup, saveSoloSetup } from '../setups';

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
  it('opens Solo at the regular pace', () => {
    expect(DEFAULT_SOLO).toEqual({ pace: 'regular' });
  });

  it('are what a player with nothing stored gets', () => {
    expect(loadSoloSetup()).toEqual(DEFAULT_SOLO);
  });
});

describe('round trip', () => {
  it('gives a saved Solo setup back', () => {
    saveSoloSetup({ pace: 'fast' });
    expect(loadSoloSetup()).toEqual({ pace: 'fast' });
  });

  it('keeps the last save, not the first', () => {
    saveSoloSetup({ pace: 'fast' });
    saveSoloSetup({ pace: 'regular' });
    expect(loadSoloSetup().pace).toBe('regular');
  });
});

describe('untrustworthy storage', () => {
  it('falls back to the defaults for anything that isn’t JSON', () => {
    store?.set('nana.setup.solo.v1', 'not json {');
    expect(loadSoloSetup()).toEqual(DEFAULT_SOLO);
  });

  it('falls back for JSON that isn’t an object', () => {
    store?.set('nana.setup.solo.v1', '[1, 2, 3]');
    expect(loadSoloSetup()).toEqual(DEFAULT_SOLO);
  });

  it('replaces a pace it can’t use', () => {
    store?.set('nana.setup.solo.v1', JSON.stringify({ pace: 'ludicrous' }));
    expect(loadSoloSetup()).toEqual(DEFAULT_SOLO);
  });

  it('reads the defaults when storage is blocked outright', () => {
    store = null;
    expect(loadSoloSetup()).toEqual(DEFAULT_SOLO);
  });

  it('swallows a write that can’t land', () => {
    store = null;
    expect(() => saveSoloSetup(DEFAULT_SOLO)).not.toThrow();
  });
});
