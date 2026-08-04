import { describe, expect, it } from 'vitest';
import {
  BLITZ_BATCH_ROUNDS,
  BLITZ_DRIP_SECONDS,
  BLITZ_INITIAL_SECONDS,
  BLITZ_MAX_BATCH,
  BLITZ_SMALL_BATCH,
  DUEL_DRIP_SECONDS,
  DUEL_PILE_LIMIT,
  DUEL_ROUND_SECONDS,
  ENDLESS_BIG_BATCH,
  ENDLESS_INITIAL_SECONDS,
  ENDLESS_SLOW_ROUNDS,
  ENDLESS_SMALL_BATCH,
  ENDLESS_SMALL_BATCH_ROUNDS,
  duelAttackMultiplier,
  duelAttackTiles,
  duelDripTiles,
  duelDripTilesAt,
  duelRoundAt,
  endlessDripSeconds,
  endlessDripTiles,
  endlessInitialSeconds,
  formatSeconds,
} from '../modes';

describe('endlessInitialSeconds', () => {
  it('gives relaxed two minutes and blitz one', () => {
    expect(endlessInitialSeconds('relaxed')).toBe(ENDLESS_INITIAL_SECONDS);
    expect(endlessInitialSeconds('relaxed')).toBe(120);
    expect(endlessInitialSeconds('blitz')).toBe(BLITZ_INITIAL_SECONDS);
    expect(endlessInitialSeconds('blitz')).toBe(60);
  });
});

describe('endlessDripSeconds, relaxed', () => {
  it('holds 45 seconds for the first five rounds', () => {
    for (let i = 0; i < ENDLESS_SLOW_ROUNDS; i++) {
      expect(endlessDripSeconds(i, 'relaxed')).toBe(45);
    }
  });

  it('tightens to 30 seconds forever after', () => {
    expect(endlessDripSeconds(ENDLESS_SLOW_ROUNDS, 'relaxed')).toBe(30);
    expect(endlessDripSeconds(10, 'relaxed')).toBe(30);
    expect(endlessDripSeconds(100, 'relaxed')).toBe(30);
  });

  it('only ever gets shorter', () => {
    for (let i = 1; i <= 30; i++) {
      expect(endlessDripSeconds(i, 'relaxed')).toBeLessThanOrEqual(
        endlessDripSeconds(i - 1, 'relaxed'),
      );
    }
  });
});

describe('endlessDripTiles, relaxed', () => {
  it('deals fives through the slow rounds and the first fast ones', () => {
    for (let i = 0; i < ENDLESS_SMALL_BATCH_ROUNDS; i++) {
      expect(endlessDripTiles(i, 'relaxed')).toBe(ENDLESS_SMALL_BATCH);
    }
  });

  it('keeps dealing fives when the clock first tightens', () => {
    // The 30-second rounds start at interval 5; the batch only grows five
    // rounds later.
    expect(endlessDripTiles(ENDLESS_SLOW_ROUNDS, 'relaxed')).toBe(ENDLESS_SMALL_BATCH);
    expect(endlessDripTiles(ENDLESS_SMALL_BATCH_ROUNDS - 1, 'relaxed')).toBe(ENDLESS_SMALL_BATCH);
  });

  it('deals sevens forever after', () => {
    expect(endlessDripTiles(ENDLESS_SMALL_BATCH_ROUNDS, 'relaxed')).toBe(ENDLESS_BIG_BATCH);
    expect(endlessDripTiles(20, 'relaxed')).toBe(ENDLESS_BIG_BATCH);
    expect(endlessDripTiles(100, 'relaxed')).toBe(ENDLESS_BIG_BATCH);
  });

  it('only ever grows', () => {
    for (let i = 1; i <= 30; i++) {
      expect(endlessDripTiles(i, 'relaxed')).toBeGreaterThanOrEqual(
        endlessDripTiles(i - 1, 'relaxed'),
      );
    }
  });
});

describe('endlessDripSeconds, blitz', () => {
  it('holds fifteen seconds forever — the batch is what grows', () => {
    for (const i of [0, 1, 7, 8, 55, 56, 500]) {
      expect(endlessDripSeconds(i, 'blitz')).toBe(BLITZ_DRIP_SECONDS);
      expect(endlessDripSeconds(i, 'blitz')).toBe(15);
    }
  });
});

describe('endlessDripTiles, blitz', () => {
  it('deals threes for the first eight rounds', () => {
    for (let i = 0; i < BLITZ_BATCH_ROUNDS; i++) {
      expect(endlessDripTiles(i, 'blitz')).toBe(BLITZ_SMALL_BATCH);
      expect(endlessDripTiles(i, 'blitz')).toBe(3);
    }
  });

  it('grows the batch by one every eight rounds', () => {
    // Two minutes at each size: eight fifteen-second rounds.
    expect(endlessDripTiles(BLITZ_BATCH_ROUNDS, 'blitz')).toBe(4);
    expect(endlessDripTiles(BLITZ_BATCH_ROUNDS * 2 - 1, 'blitz')).toBe(4);
    expect(endlessDripTiles(BLITZ_BATCH_ROUNDS * 2, 'blitz')).toBe(5);
    expect(endlessDripTiles(BLITZ_BATCH_ROUNDS * 3, 'blitz')).toBe(6);
  });

  it('tops out at ten and stays there', () => {
    // Three grown seven times: round 56 is the first to deal ten.
    const firstMaxRound = BLITZ_BATCH_ROUNDS * (BLITZ_MAX_BATCH - BLITZ_SMALL_BATCH);
    expect(firstMaxRound).toBe(56);
    expect(endlessDripTiles(firstMaxRound - 1, 'blitz')).toBe(BLITZ_MAX_BATCH - 1);
    expect(endlessDripTiles(firstMaxRound, 'blitz')).toBe(BLITZ_MAX_BATCH);
    expect(endlessDripTiles(1000, 'blitz')).toBe(BLITZ_MAX_BATCH);
  });

  it('only ever grows', () => {
    for (let i = 1; i <= 120; i++) {
      expect(endlessDripTiles(i, 'blitz')).toBeGreaterThanOrEqual(
        endlessDripTiles(i - 1, 'blitz'),
      );
    }
  });

  it('is never gentler than relaxed on either dial', () => {
    for (let i = 0; i <= 60; i++) {
      expect(endlessDripSeconds(i, 'blitz')).toBeLessThan(endlessDripSeconds(i, 'relaxed'));
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
