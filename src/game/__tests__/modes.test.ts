import { describe, expect, it } from 'vitest';
import {
  BATTLE_MAX_PLAYERS,
  BATTLE_MIN_PLAYERS,
  FAST_BATCH_ROUNDS,
  FAST_DRIP_SECONDS,
  FAST_INITIAL_SECONDS,
  FAST_MAX_BATCH,
  FAST_SMALL_BATCH,
  DUEL_DRIP_SECONDS,
  DUEL_PILE_LIMIT,
  DUEL_ROUND_SECONDS,
  ENDLESS_BIG_BATCH,
  ENDLESS_INITIAL_SECONDS,
  ENDLESS_SLOW_ROUNDS,
  ENDLESS_SMALL_BATCH,
  ENDLESS_SMALL_BATCH_ROUNDS,
  PUZZLE_LOCK_OPTIONS,
  PUZZLE_START_TILES,
  duelAttackMultiplier,
  duelAttackTiles,
  duelDripTiles,
  duelDripTilesAt,
  duelRoundAt,
  endlessDripSeconds,
  endlessDripTiles,
  endlessInitialSeconds,
  formatSeconds,
  puzzleRefillTiles,
  splitAttackTiles,
} from '../modes';

describe('endlessInitialSeconds', () => {
  it('gives regular two minutes and fast one', () => {
    expect(endlessInitialSeconds('regular')).toBe(ENDLESS_INITIAL_SECONDS);
    expect(endlessInitialSeconds('regular')).toBe(120);
    expect(endlessInitialSeconds('fast')).toBe(FAST_INITIAL_SECONDS);
    expect(endlessInitialSeconds('fast')).toBe(60);
  });
});

describe('endlessDripSeconds, regular', () => {
  it('holds 45 seconds for the first five rounds', () => {
    for (let i = 0; i < ENDLESS_SLOW_ROUNDS; i++) {
      expect(endlessDripSeconds(i, 'regular')).toBe(45);
    }
  });

  it('tightens to 30 seconds forever after', () => {
    expect(endlessDripSeconds(ENDLESS_SLOW_ROUNDS, 'regular')).toBe(30);
    expect(endlessDripSeconds(10, 'regular')).toBe(30);
    expect(endlessDripSeconds(100, 'regular')).toBe(30);
  });

  it('only ever gets shorter', () => {
    for (let i = 1; i <= 30; i++) {
      expect(endlessDripSeconds(i, 'regular')).toBeLessThanOrEqual(
        endlessDripSeconds(i - 1, 'regular'),
      );
    }
  });
});

describe('endlessDripTiles, regular', () => {
  it('deals fives through the slow rounds and the first fast ones', () => {
    for (let i = 0; i < ENDLESS_SMALL_BATCH_ROUNDS; i++) {
      expect(endlessDripTiles(i, 'regular')).toBe(ENDLESS_SMALL_BATCH);
    }
  });

  it('keeps dealing fives when the clock first tightens', () => {
    // The 30-second rounds start at interval 5; the batch only grows five
    // rounds later.
    expect(endlessDripTiles(ENDLESS_SLOW_ROUNDS, 'regular')).toBe(ENDLESS_SMALL_BATCH);
    expect(endlessDripTiles(ENDLESS_SMALL_BATCH_ROUNDS - 1, 'regular')).toBe(ENDLESS_SMALL_BATCH);
  });

  it('deals sevens forever after', () => {
    expect(endlessDripTiles(ENDLESS_SMALL_BATCH_ROUNDS, 'regular')).toBe(ENDLESS_BIG_BATCH);
    expect(endlessDripTiles(20, 'regular')).toBe(ENDLESS_BIG_BATCH);
    expect(endlessDripTiles(100, 'regular')).toBe(ENDLESS_BIG_BATCH);
  });

  it('only ever grows', () => {
    for (let i = 1; i <= 30; i++) {
      expect(endlessDripTiles(i, 'regular')).toBeGreaterThanOrEqual(
        endlessDripTiles(i - 1, 'regular'),
      );
    }
  });
});

describe('endlessDripSeconds, fast', () => {
  it('holds fifteen seconds forever — the batch is what grows', () => {
    for (const i of [0, 1, 7, 8, 55, 56, 500]) {
      expect(endlessDripSeconds(i, 'fast')).toBe(FAST_DRIP_SECONDS);
      expect(endlessDripSeconds(i, 'fast')).toBe(15);
    }
  });
});

describe('endlessDripTiles, fast', () => {
  it('deals threes for the first eight rounds', () => {
    for (let i = 0; i < FAST_BATCH_ROUNDS; i++) {
      expect(endlessDripTiles(i, 'fast')).toBe(FAST_SMALL_BATCH);
      expect(endlessDripTiles(i, 'fast')).toBe(3);
    }
  });

  it('grows the batch by one every eight rounds', () => {
    // Two minutes at each size: eight fifteen-second rounds.
    expect(endlessDripTiles(FAST_BATCH_ROUNDS, 'fast')).toBe(4);
    expect(endlessDripTiles(FAST_BATCH_ROUNDS * 2 - 1, 'fast')).toBe(4);
    expect(endlessDripTiles(FAST_BATCH_ROUNDS * 2, 'fast')).toBe(5);
    expect(endlessDripTiles(FAST_BATCH_ROUNDS * 3, 'fast')).toBe(6);
  });

  it('tops out at ten and stays there', () => {
    // Three grown seven times: round 56 is the first to deal ten.
    const firstMaxRound = FAST_BATCH_ROUNDS * (FAST_MAX_BATCH - FAST_SMALL_BATCH);
    expect(firstMaxRound).toBe(56);
    expect(endlessDripTiles(firstMaxRound - 1, 'fast')).toBe(FAST_MAX_BATCH - 1);
    expect(endlessDripTiles(firstMaxRound, 'fast')).toBe(FAST_MAX_BATCH);
    expect(endlessDripTiles(1000, 'fast')).toBe(FAST_MAX_BATCH);
  });

  it('only ever grows', () => {
    for (let i = 1; i <= 120; i++) {
      expect(endlessDripTiles(i, 'fast')).toBeGreaterThanOrEqual(
        endlessDripTiles(i - 1, 'fast'),
      );
    }
  });

  it('is never gentler than regular on either dial', () => {
    for (let i = 0; i <= 60; i++) {
      expect(endlessDripSeconds(i, 'fast')).toBeLessThan(endlessDripSeconds(i, 'regular'));
    }
  });
});

describe('duelRoundAt', () => {
  it('splits the game into three-minute rounds, final round forever', () => {
    expect(duelRoundAt(0)).toBe(1);
    expect(duelRoundAt(DUEL_ROUND_SECONDS - 1)).toBe(1);
    expect(duelRoundAt(DUEL_ROUND_SECONDS)).toBe(2);
    expect(duelRoundAt(DUEL_ROUND_SECONDS * 2 - 1)).toBe(2);
    expect(duelRoundAt(DUEL_ROUND_SECONDS * 2)).toBe(3);
    expect(duelRoundAt(DUEL_ROUND_SECONDS * 10)).toBe(3);
  });
});

describe('duelDripTiles', () => {
  it('brings one, then two, then four tiles a drip', () => {
    expect(duelDripTiles(1)).toBe(1);
    expect(duelDripTiles(2)).toBe(2);
    expect(duelDripTiles(3)).toBe(4);
  });

  it('clamps rounds outside the game', () => {
    expect(duelDripTiles(0)).toBe(1);
    expect(duelDripTiles(9)).toBe(4);
  });
});

describe('duelDripTilesAt', () => {
  it('sizes each drip by the round it lands in', () => {
    const dripsPerRound = DUEL_ROUND_SECONDS / DUEL_DRIP_SECONDS; // 9
    // Drips 0..7 land inside round one (at 20s..160s); the drip at 180s
    // opens round two.
    for (let i = 0; i < dripsPerRound - 1; i++) {
      expect(duelDripTilesAt(i)).toBe(1);
    }
    expect(duelDripTilesAt(dripsPerRound - 1)).toBe(2);
    expect(duelDripTilesAt(dripsPerRound * 2 - 1)).toBe(4);
    expect(duelDripTilesAt(100)).toBe(4);
  });
});

describe('duelAttackMultiplier', () => {
  it('scales rounds at ×1, ×1.5, ×2', () => {
    expect(duelAttackMultiplier(1)).toBe(1);
    expect(duelAttackMultiplier(2)).toBe(1.5);
    expect(duelAttackMultiplier(3)).toBe(2);
  });
});

describe('duelAttackTiles', () => {
  it('sends nothing for short words', () => {
    expect(duelAttackTiles(2, 1)).toBe(0);
    expect(duelAttackTiles(3, 1)).toBe(0);
    expect(duelAttackTiles(3, 3)).toBe(0);
  });

  it('sends one tile per letter past three in round one', () => {
    expect(duelAttackTiles(4, 1)).toBe(1);
    expect(duelAttackTiles(5, 1)).toBe(2);
    expect(duelAttackTiles(6, 1)).toBe(3);
    expect(duelAttackTiles(8, 1)).toBe(5);
  });

  it('scales up by half in round two', () => {
    expect(duelAttackTiles(4, 2)).toBe(2); // 1 × 1.5 rounds up
    expect(duelAttackTiles(5, 2)).toBe(3);
    expect(duelAttackTiles(6, 2)).toBe(5); // 4.5 rounds up
  });

  it('doubles in the final round', () => {
    expect(duelAttackTiles(4, 3)).toBe(2);
    expect(duelAttackTiles(5, 3)).toBe(4);
    expect(duelAttackTiles(6, 3)).toBe(6);
  });

  it('pays only the growth when a word is extended', () => {
    // HEART (worth 2) stretched to HEARTS (worth 3) earns the difference.
    expect(duelAttackTiles(6, 1, [5])).toBe(1);
    // CAT was worth nothing, so CATS earns its full value.
    expect(duelAttackTiles(4, 1, [3])).toBe(1);
    // Adding nothing of value sends nothing.
    expect(duelAttackTiles(4, 1, [4])).toBe(0);
  });

  it('subtracts every word a placement bridges together', () => {
    // Two 4-letter words (worth 1 each) joined into a 9-letter word (worth 6).
    expect(duelAttackTiles(9, 1, [4, 4])).toBe(4);
  });

  it('scales the growth by the round multiplier', () => {
    // One letter of growth, ×1.5 rounds up to 2 — the multiplier applies to
    // the difference, not to each word before subtracting.
    expect(duelAttackTiles(6, 2, [5])).toBe(2);
    expect(duelAttackTiles(6, 3, [5])).toBe(2);
  });

  it('treats an empty history as a brand-new word', () => {
    expect(duelAttackTiles(6, 1, [])).toBe(duelAttackTiles(6, 1));
  });
});

describe('duel constants', () => {
  it('caps the pile at twenty-five', () => {
    expect(DUEL_PILE_LIMIT).toBe(25);
  });
});

describe('battle constants', () => {
  it('seats two to eight players', () => {
    expect(BATTLE_MIN_PLAYERS).toBe(2);
    expect(BATTLE_MAX_PLAYERS).toBe(8);
  });
});

describe('splitAttackTiles', () => {
  it('hands a duel-sized field the whole attack', () => {
    expect(splitAttackTiles(4, 1)).toEqual([4]);
    expect(splitAttackTiles(1, 1)).toEqual([1]);
  });

  it('splits evenly when the attack divides', () => {
    expect(splitAttackTiles(6, 3)).toEqual([2, 2, 2]);
    expect(splitAttackTiles(7, 7)).toEqual([1, 1, 1, 1, 1, 1, 1]);
  });

  it('always sums to the attack — a single tile still lands somewhere', () => {
    for (let count = 0; count <= 12; count++) {
      for (let targets = 1; targets <= 7; targets++) {
        const shares = splitAttackTiles(count, targets);
        expect(shares).toHaveLength(targets);
        expect(shares.reduce((sum, share) => sum + share, 0)).toBe(count);
      }
    }
  });

  it('lands the remainder from the given seat, wrapping round', () => {
    expect(splitAttackTiles(5, 3, 0)).toEqual([2, 2, 1]);
    expect(splitAttackTiles(5, 3, 1)).toEqual([1, 2, 2]);
    expect(splitAttackTiles(5, 3, 2)).toEqual([2, 1, 2]);
    // The rotation is a courtesy, not a requirement — any offset still sums.
    expect(splitAttackTiles(5, 3, 7)).toEqual([1, 2, 2]);
    expect(splitAttackTiles(5, 3, -1)).toEqual([2, 1, 2]);
  });

  it('never scales the total up with the size of the room', () => {
    // Eight players: seven targets take, between them, exactly what a duel's
    // one opponent would — the room makes each hit smaller, not the game
    // harder.
    const duelAttack = duelAttackTiles(8, 3); // a big final-round word
    const shares = splitAttackTiles(duelAttack, 7);
    expect(shares.reduce((sum, share) => sum + share, 0)).toBe(duelAttack);
    for (const share of shares) expect(share).toBeLessThanOrEqual(Math.ceil(duelAttack / 7));
  });

  it('shrugs off nonsense', () => {
    expect(splitAttackTiles(5, 0)).toEqual([]);
    expect(splitAttackTiles(-3, 4)).toEqual([0, 0, 0, 0]);
    expect(splitAttackTiles(Number.NaN, 4)).toEqual([]);
  });
});

describe('puzzleRefillTiles', () => {
  it('tops a spent pile back up to the opening twenty', () => {
    expect(puzzleRefillTiles(15)).toBe(5);
    expect(puzzleRefillTiles(0)).toBe(PUZZLE_START_TILES);
  });

  it('deals nothing to a pile already at twenty', () => {
    expect(puzzleRefillTiles(PUZZLE_START_TILES)).toBe(0);
  });

  // A word taken back off a flexible board puts its letters in the pile,
  // which can carry it past twenty. Paying that pile out again would grow it
  // without end.
  it('deals nothing to a pile already over twenty', () => {
    expect(puzzleRefillTiles(PUZZLE_START_TILES + 7)).toBe(0);
  });
});

describe('puzzle setup options', () => {
  it('offers both tile placements, flexible first', () => {
    expect(PUZZLE_LOCK_OPTIONS.map((option) => option.lock)).toEqual(['flexible', 'locked']);
  });

  it('names them for the setup sheet', () => {
    expect(PUZZLE_LOCK_OPTIONS.map((option) => option.name)).toEqual(['Flexible', 'Locked']);
  });
});

describe('formatSeconds', () => {
  it('formats whole minutes', () => {
    expect(formatSeconds(180)).toBe('3:00');
    expect(formatSeconds(60)).toBe('1:00');
  });

  it('pads seconds to two digits', () => {
    expect(formatSeconds(75)).toBe('1:15');
    expect(formatSeconds(9)).toBe('0:09');
  });

  it('clamps at zero', () => {
    expect(formatSeconds(0)).toBe('0:00');
    expect(formatSeconds(-3)).toBe('0:00');
  });
});
