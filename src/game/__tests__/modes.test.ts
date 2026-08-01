import { describe, expect, it } from 'vitest';
import { ENDLESS_DRIP_STAGES, endlessDripSeconds, formatSeconds, timedLevelSeconds } from '../modes';
import { LEVEL_COUNT } from '../levels';

describe('timedLevelSeconds', () => {
  it('gives three minutes for the first level', () => {
    expect(timedLevelSeconds(1)).toBe(180);
  });

  it('gives two minutes for the second level', () => {
    expect(timedLevelSeconds(2)).toBe(120);
  });

  it('takes 15 seconds off each level after the second', () => {
    expect(timedLevelSeconds(3)).toBe(105);
    expect(timedLevelSeconds(4)).toBe(90);
    expect(timedLevelSeconds(5)).toBe(75);
  });

  it('never reaches zero within the game', () => {
    for (let level = 1; level <= LEVEL_COUNT; level++) {
      expect(timedLevelSeconds(level)).toBeGreaterThan(0);
    }
  });
});

describe('endlessDripSeconds', () => {
  it('holds a minute for the first three intervals', () => {
    expect(endlessDripSeconds(0)).toBe(60);
    expect(endlessDripSeconds(1)).toBe(60);
    expect(endlessDripSeconds(2)).toBe(60);
  });

  it('drops to 45 seconds after three intervals, and 30 after three more', () => {
    expect(endlessDripSeconds(3)).toBe(45);
    expect(endlessDripSeconds(5)).toBe(45);
    expect(endlessDripSeconds(6)).toBe(30);
  });

  it('stays at the last stage forever after', () => {
    expect(endlessDripSeconds(7)).toBe(30);
    expect(endlessDripSeconds(100)).toBe(30);
  });

  it('only ever gets shorter', () => {
    for (let i = 1; i <= 20; i++) {
      expect(endlessDripSeconds(i)).toBeLessThanOrEqual(endlessDripSeconds(i - 1));
    }
    expect(endlessDripSeconds(20)).toBe(ENDLESS_DRIP_STAGES[ENDLESS_DRIP_STAGES.length - 1]);
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
