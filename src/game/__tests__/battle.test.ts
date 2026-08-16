import { describe, expect, it } from 'vitest';
import {
  battleOver,
  battleWinner,
  battleWinners,
  createTileStream,
  isValidBattleCode,
  newBattleCode,
  normalizeBattleCode,
  ordinal,
  rankByElimination,
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

  it('serves requests smaller than a word — attacks ask for one tile', () => {
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

describe('battleOver / battleWinner', () => {
  it('is not decided before two players are dealt in', () => {
    expect(battleOver([player()])).toBe(false);
    expect(battleOver([player(), player({ waiting: true })])).toBe(false);
  });

  it('plays on while two players are alive', () => {
    expect(battleOver([player(), player()])).toBe(false);
  });

  it('ends the moment the field is down to one, and names the survivor', () => {
    const survivor = player({ score: 12 });
    const players = [survivor, player({ buried: true })];
    expect(battleOver(players)).toBe(true);
    expect(battleWinner(players)).toBe(survivor);
  });

  it('ends when the last rival leaves for good', () => {
    const survivor = player();
    const players = [survivor, player({ left: true })];
    expect(battleOver(players)).toBe(true);
    expect(battleWinner(players)).toBe(survivor);
  });

  it('calls a draw when everyone is gone', () => {
    const players = [player({ buried: true }), player({ buried: true })];
    expect(battleOver(players)).toBe(true);
    expect(battleWinner(players)).toBeNull();
  });

  it('referees a full field of eight: last one standing', () => {
    // Seven of eight down — the game runs until exactly one is left.
    const field = (alive: number) =>
      Array.from({ length: 8 }, (_, i) => player({ buried: i >= alive }));
    expect(battleOver(field(3))).toBe(false);
    expect(battleOver(field(2))).toBe(false);
    const done = field(1);
    expect(battleOver(done)).toBe(true);
    expect(battleWinner(done)).toBe(done[0]);
  });
});

describe('rankByElimination', () => {
  function faller(outOrder: number | null, overrides: Partial<Contestant> = {}) {
    return { ...player({ buried: outOrder !== null, ...overrides }), outOrder };
  }

  it('leads with the survivor and walks back through the falls', () => {
    const winner = faller(null);
    const first = faller(1);
    const second = faller(2);
    const third = faller(3);
    const ranked = rankByElimination([first, third, winner, second]);
    expect(ranked.map((r) => r.player)).toEqual([winner, third, second, first]);
    expect(ranked.map((r) => r.rank)).toEqual([1, 2, 3, 4]);
  });

  it('shares the top rank in a draw where nobody survived', () => {
    // The theoretical draw: the last two went down together, so the two
    // never-marked entries would both be survivors — but here everyone
    // fell, and the two who share an outOrder share a rank.
    const ranked = rankByElimination([faller(null), faller(null), faller(1)]);
    expect(ranked.map((r) => r.rank)).toEqual([1, 1, 3]);
  });

  it('ranks a leaver by when they left, like any other fall', () => {
    const winner = faller(null);
    const quitter = faller(1, { buried: false, left: true });
    const fighter = faller(2);
    const ranked = rankByElimination([quitter, winner, fighter]);
    expect(ranked.map((r) => r.player)).toEqual([winner, fighter, quitter]);
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
      outOrder: null,
      ...overrides,
    };
  }

  function state(players: BattlePlayer[], winnerId: string | null = null) {
    return { phase: 'finished' as const, players, game: 1, winnerId };
  }

  it('gives the battle to the last one standing, whatever the scores say', () => {
    const winners = battleWinners(
      state(
        [
          seat('a', { score: 99, buried: true, outOrder: 2 }),
          seat('b', { score: 1 }),
          seat('c', { score: 50, buried: true, outOrder: 1 }),
        ],
        'b',
      ),
    );
    expect(winners.map((p) => p.id)).toEqual(['b']);
  });

  it('gives a drawn battle to nobody', () => {
    const winners = battleWinners(
      state(
        [seat('a', { buried: true, outOrder: 1 }), seat('b', { buried: true, outOrder: 2 })],
        null,
      ),
    );
    expect(winners).toEqual([]);
  });

  it('never crowns a player who sat the game out', () => {
    // A winnerId pointing at a waiting player names nobody — contestants only.
    const winners = battleWinners(
      state([seat('a', { buried: true, outOrder: 1 }), seat('w', { waiting: true })], 'w'),
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
