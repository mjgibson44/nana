import { describe, expect, it } from 'vitest';
import {
  battleOver,
  createTileStream,
  isValidBattleCode,
  newBattleCode,
  normalizeBattleCode,
  ordinal,
  rankPlayers,
  type Contestant,
} from '../battle';
import { seededRng } from '../rng';

function player(overrides: Partial<Contestant> = {}): Contestant {
  return { score: 0, buried: false, connected: true, waiting: false, ...overrides };
}

describe('seededRng', () => {
  it('repeats exactly for the same seed', () => {
    const a = seededRng('banana');
    const b = seededRng('banana');
    for (let i = 0; i < 1000; i++) {
      expect(a()).toBe(b());
    }
  });

  it('differs between seeds and stays in [0, 1)', () => {
    const a = seededRng('banana');
    const b = seededRng('bananb');
    let same = 0;
    for (let i = 0; i < 1000; i++) {
      const x = a();
      const y = b();
      expect(x).toBeGreaterThanOrEqual(0);
      expect(x).toBeLessThan(1);
      if (x === y) same++;
    }
    expect(same).toBeLessThan(5);
  });
});

describe('createTileStream', () => {
  it('deals identical batches to every stream with the same seed', () => {
    // The real battle pattern: an opening 20, then fives for a long game —
    // however a player earns them, batch N is batch N.
    const counts = [20, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5];
    for (let round = 0; round < 5; round++) {
      const seed = `game-${round}`;
      const a = createTileStream(seed);
      const b = createTileStream(seed);
      for (const count of counts) {
        const batchA = a.next(count);
        const batchB = b.next(count);
        expect(batchA).toHaveLength(count);
        expect(batchA.join('')).toMatch(/^[a-z]+$/);
        expect(batchA).toEqual(batchB);
      }
    }
  });

  it('deals different games for different seeds', () => {
    const a = createTileStream('seed-one').next(20);
    const b = createTileStream('seed-two').next(20);
    expect(a.join('')).not.toBe(b.join(''));
  });
});

describe('battle codes', () => {
  it('generates valid codes', () => {
    for (let i = 0; i < 100; i++) {
      expect(isValidBattleCode(newBattleCode())).toBe(true);
    }
  });

  it('forgives spacing, case, and lookalike characters', () => {
    expect(normalizeBattleCode('  ab-cde ')).toBe('ABCDE');
    expect(normalizeBattleCode('a0cd1')).toBe('AOCDI');
  });

  it('rejects the wrong shape', () => {
    expect(isValidBattleCode('')).toBe(false);
    expect(isValidBattleCode('ABC')).toBe(false);
    expect(isValidBattleCode('ABCDEF')).toBe(false);
    expect(isValidBattleCode('AB1DE')).toBe(false); // 1 isn't in the alphabet
  });
});

describe('battleOver', () => {
  it('is not over while several players are still standing', () => {
    expect(battleOver([player({ score: 50 }), player({ score: 10 })])).toBe(false);
  });

  it('ends when every player is buried', () => {
    expect(
      battleOver([player({ buried: true, score: 30 }), player({ buried: true, score: 12 })]),
    ).toBe(true);
  });

  it('ends when the last player standing is already strictly ahead', () => {
    expect(
      battleOver([player({ score: 40 }), player({ buried: true, score: 30 })]),
    ).toBe(true);
  });

  it('plays on while the last player standing is behind or tied', () => {
    expect(
      battleOver([player({ score: 20 }), player({ buried: true, score: 30 })]),
    ).toBe(false);
    expect(
      battleOver([player({ score: 30 }), player({ buried: true, score: 30 })]),
    ).toBe(false);
  });

  it('never ends a solo game just for being solo', () => {
    expect(battleOver([player({ score: 100 })])).toBe(false);
    expect(battleOver([player({ score: 100, buried: true })])).toBe(true);
  });

  it('treats a disconnected player as out of the running', () => {
    // The survivor leads the disconnected player's frozen score, so it's over.
    expect(
      battleOver([player({ score: 40 }), player({ score: 10, connected: false })]),
    ).toBe(true);
    // Everyone left; nobody can move the game forward.
    expect(
      battleOver([
        player({ score: 40, connected: false }),
        player({ score: 10, connected: false }),
      ]),
    ).toBe(true);
  });

  it('ignores players waiting for the next game', () => {
    expect(
      battleOver([player({ score: 5, buried: true }), player({ score: 0, waiting: true })]),
    ).toBe(true);
    expect(battleOver([player({ waiting: true })])).toBe(false);
  });
});

describe('rankPlayers', () => {
  it('ranks by score, best first', () => {
    const ranked = rankPlayers([
      player({ score: 10 }),
      player({ score: 30 }),
      player({ score: 20 }),
    ]);
    expect(ranked.map((r) => r.player.score)).toEqual([30, 20, 10]);
    expect(ranked.map((r) => r.rank)).toEqual([1, 2, 3]);
  });

  it('shares ranks on ties and skips past them', () => {
    const ranked = rankPlayers([
      player({ score: 20 }),
      player({ score: 30 }),
      player({ score: 20 }),
      player({ score: 10 }),
    ]);
    expect(ranked.map((r) => r.rank)).toEqual([1, 2, 2, 4]);
  });
});

describe('ordinal', () => {
  it('spells ranks the way people say them', () => {
    expect(ordinal(1)).toBe('1st');
    expect(ordinal(2)).toBe('2nd');
    expect(ordinal(3)).toBe('3rd');
    expect(ordinal(4)).toBe('4th');
    expect(ordinal(11)).toBe('11th');
    expect(ordinal(12)).toBe('12th');
    expect(ordinal(13)).toBe('13th');
    expect(ordinal(21)).toBe('21st');
    expect(ordinal(22)).toBe('22nd');
  });
});
