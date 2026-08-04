import { describe, expect, it } from 'vitest';
import {
  battleOver,
  battleWinners,
  createTileStream,
  duelOver,
  duelWinner,
  isValidBattleCode,
  newBattleCode,
  normalizeBattleCode,
  ordinal,
  rankPlayers,
  type BattleMode,
  type BattlePlayer,
  type Contestant,
} from '../battle';
import { seededRng } from '../rng';

function player(overrides: Partial<Contestant> = {}): Contestant {
  return { score: 0, buried: false, left: false, waiting: false, ...overrides };
}

describe('seededRng', () => {
  it('repeats exactly for the same seed', () => {
    const a = seededRng('pepper');
    const b = seededRng('pepper');
    for (let i = 0; i < 1000; i++) {
      expect(a()).toBe(b());
    }
  });

  it('differs between seeds and stays in [0, 1)', () => {
    const a = seededRng('pepper');
    const b = seededRng('peppes');
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

  it('deals the same letter sequence however the requests are sized', () => {
    // Late-game drips grow to eights and tens while pile-clears stay at
    // five, so two players' request sizes interleave differently. The
    // letters must not: same seed, same sequence, just cut differently.
    const seed = 'chunky';
    const a = createTileStream(seed);
    const b = createTileStream(seed);
    expect(a.next(20)).toEqual(b.next(20));
    const lettersA = [5, 8, 5, 10, 8].flatMap((count) => a.next(count));
    const lettersB = [8, 5, 5, 8, 10].flatMap((count) => b.next(count));
    expect(lettersA).toEqual(lettersB);
  });

  it('deals different games for different seeds', () => {
    const a = createTileStream('seed-one').next(20);
    const b = createTileStream('seed-two').next(20);
    expect(a.join('')).not.toBe(b.join(''));
  });

  it('serves requests smaller than a word — duel attacks ask for one tile', () => {
    const stream = createTileStream('attacks');
    expect(stream.next(1)).toHaveLength(1);
    expect(stream.next(2)).toHaveLength(2);
    expect(stream.next(4)).toHaveLength(4);
    for (const letter of stream.next(1)) expect(letter).toMatch(/^[a-z]$/);
  });
});

describe('battle codes', () => {
  it('generates valid codes', () => {
    for (let i = 0; i < 100; i++) {
      expect(isValidBattleCode(newBattleCode())).toBe(true);
    }
  });

  it('generates letters only — never a digit', () => {
    for (let i = 0; i < 200; i++) {
      expect(newBattleCode()).toMatch(/^[A-Z]{5}$/);
    }
  });

  it('forgives spacing and case, and drops characters no code contains', () => {
    expect(normalizeBattleCode('  ab-cde ')).toBe('ABCDE');
    expect(normalizeBattleCode('ab cd e')).toBe('ABCDE');
    expect(normalizeBattleCode('a0cd1')).toBe('ACD');
  });

  it('rejects the wrong shape', () => {
    expect(isValidBattleCode('')).toBe(false);
    expect(isValidBattleCode('ABC')).toBe(false);
    expect(isValidBattleCode('ABCDEF')).toBe(false);
    expect(isValidBattleCode('AB1DE')).toBe(false); // digits are out entirely
    expect(isValidBattleCode('ABIDE')).toBe(false); // I is not in the alphabet
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

  it('treats a player who left for good as out of the running', () => {
    // The survivor leads the leaver's frozen score, so it's over.
    expect(
      battleOver([player({ score: 40 }), player({ score: 10, left: true })]),
    ).toBe(true);
    // Everyone left; nobody can move the game forward.
    expect(
      battleOver([
        player({ score: 40, left: true }),
        player({ score: 10, left: true }),
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

describe('duelOver / duelWinner', () => {
  it('is not decided before two players are dealt in', () => {
    expect(duelOver([player()])).toBe(false);
    expect(duelOver([player(), player({ waiting: true })])).toBe(false);
  });

  it('plays on while both duellists are alive', () => {
    expect(duelOver([player(), player()])).toBe(false);
  });

  it('ends the moment one goes under, and names the survivor', () => {
    const survivor = player({ score: 12 });
    const players = [survivor, player({ buried: true })];
    expect(duelOver(players)).toBe(true);
    expect(duelWinner(players)).toBe(survivor);
  });

  it('ends when one leaves for good', () => {
    const survivor = player();
    const players = [survivor, player({ left: true })];
    expect(duelOver(players)).toBe(true);
    expect(duelWinner(players)).toBe(survivor);
  });

  it('calls a draw when both are gone', () => {
    const players = [player({ buried: true }), player({ buried: true })];
    expect(duelOver(players)).toBe(true);
    expect(duelWinner(players)).toBeNull();
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

describe('battleWinners', () => {
  function seat(id: string, overrides: Partial<BattlePlayer> = {}): BattlePlayer {
    return {
      id,
      name: id,
      host: false,
      score: 0,
      buried: false,
      connected: true,
      left: false,
      waiting: false,
      tiles: 0,
      ...overrides,
    };
  }

  function state(mode: BattleMode, players: BattlePlayer[], winnerId: string | null = null) {
    return { mode, phase: 'finished' as const, players, game: 1, paused: false, winnerId };
  }

  it('gives an Endless Battle to the top score', () => {
    const winners = battleWinners(
      state('endless', [seat('a', { score: 10 }), seat('b', { score: 30 })]),
    );
    expect(winners.map((p) => p.id)).toEqual(['b']);
  });

  it('gives a tied Endless Battle to everyone who shares the top score', () => {
    const winners = battleWinners(
      state('endless', [
        seat('a', { score: 30 }),
        seat('b', { score: 20 }),
        seat('c', { score: 30 }),
      ]),
    );
    expect(winners.map((p) => p.id).sort()).toEqual(['a', 'c']);
  });

  it('leaves out players who sat the game out, however well they scored', () => {
    const winners = battleWinners(
      state('endless', [
        seat('a', { score: 10 }),
        seat('latecomer', { score: 999, waiting: true }),
      ]),
    );
    expect(winners.map((p) => p.id)).toEqual(['a']);
  });

  it('gives a Duel to the survivor the host named, whatever the scores say', () => {
    const winners = battleWinners(
      state('duel', [seat('a', { score: 99, buried: true }), seat('b', { score: 1 })], 'b'),
    );
    expect(winners.map((p) => p.id)).toEqual(['b']);
  });

  it('gives a drawn Duel to nobody', () => {
    const winners = battleWinners(
      state('duel', [seat('a', { buried: true }), seat('b', { buried: true })], null),
    );
    expect(winners).toEqual([]);
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
