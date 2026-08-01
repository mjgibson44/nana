import { describe, expect, it } from 'vitest';
import { validateBoard } from '../board';
import { COMMON_WORDS } from '../commonWords';
import { extendPuzzle, generatePuzzle } from '../generator';
import { BOARD_SIZE, tilesAddedForLevel } from '../levels';
import type { TileMap } from '../types';
import { parseKey } from '../types';

const generationDict = new Set(COMMON_WORDS);

function sortedLetters(letters: string[]): string {
  return letters.slice().sort().join('');
}

describe('generatePuzzle', () => {
  it('deals exactly 20 letters backed by a known-valid connected solution', () => {
    for (let i = 0; i < 50; i++) {
      const puzzle = generatePuzzle(COMMON_WORDS, 20);

      expect(puzzle.letters).toHaveLength(20);
      expect(puzzle.letters.join('')).toMatch(/^[a-z]{20}$/);

      // The crossword builder should essentially always succeed with a
      // 5,000-word pool — the fallback is a safety net, not the normal path.
      expect(puzzle.solution).not.toBeNull();

      const validation = validateBoard(puzzle.solution!, generationDict);
      expect(validation.ok).toBe(true);
      expect(validation.tileCount).toBe(20);

      // The dealt letters are exactly the letters of the hidden solution.
      expect(sortedLetters(puzzle.letters)).toBe(
        sortedLetters(Object.values(puzzle.solution!)),
      );
    }
  });

  it('supports other tile counts', () => {
    for (const count of [12, 15, 21, 30]) {
      const puzzle = generatePuzzle(COMMON_WORDS, count);
      expect(puzzle.letters).toHaveLength(count);
      if (puzzle.solution) {
        const validation = validateBoard(puzzle.solution, generationDict);
        expect(validation.ok).toBe(true);
        expect(validation.tileCount).toBe(count);
      }
    }
  });

  it('draws from multiple source words for variety', () => {
    const puzzle = generatePuzzle(COMMON_WORDS, 20);
    expect(puzzle.sourceWords.length).toBeGreaterThanOrEqual(3);
    for (const word of puzzle.sourceWords) {
      expect(generationDict.has(word)).toBe(true);
    }
  });
});

describe('extendPuzzle', () => {
  /** Centre a puzzle's solution on the real board, the way level one does. */
  function openingBoard(): TileMap {
    const puzzle = generatePuzzle(COMMON_WORDS, 20);
    const board: TileMap = {};
    const offset = 6;
    for (const [key, letter] of Object.entries(puzzle.solution!)) {
      const { row, col } = parseKey(key);
      board[`${row + offset},${col + offset}`] = letter;
    }
    return board;
  }

  it('adds exactly the letters asked for, leaving the board alone', () => {
    for (let i = 0; i < 25; i++) {
      const board = openingBoard();
      const before = { ...board };
      const dealt = extendPuzzle(board, BOARD_SIZE, COMMON_WORDS, 10);

      expect(dealt.letters).toHaveLength(10);
      expect(dealt.letters.join('')).toMatch(/^[a-z]{10}$/);
      // The generator must not mutate the board it was handed.
      expect(board).toEqual(before);
    }
  });

  /**
   * The guarantee the levels rest on: the new letters can all be played onto
   * the board *as it already stands*, keeping every existing tile in place.
   */
  it('grows an arrangement that plays every new letter onto the board as built', () => {
    for (let i = 0; i < 25; i++) {
      const board = openingBoard();
      const dealt = extendPuzzle(board, BOARD_SIZE, COMMON_WORDS, 10);
      expect(dealt.solution).not.toBeNull();
      const solved = dealt.solution!;

      // Every tile already down is untouched, and in the same place.
      for (const [key, letter] of Object.entries(board)) {
        expect(solved[key]).toBe(letter);
      }
      // It adds exactly the 10 dealt letters and nothing else.
      const added = Object.keys(solved).filter((key) => !(key in board));
      expect(added).toHaveLength(10);
      expect(sortedLetters(added.map((key) => solved[key]))).toBe(
        sortedLetters(dealt.letters),
      );
      // It stays on the board...
      for (const key of added) {
        const { row, col } = parseKey(key);
        expect(row).toBeGreaterThanOrEqual(0);
        expect(col).toBeGreaterThanOrEqual(0);
        expect(row).toBeLessThan(BOARD_SIZE);
        expect(col).toBeLessThan(BOARD_SIZE);
      }
      // ...and it's a fully legal crossword, so the arrangement really is playable.
      const validation = validateBoard(solved, generationDict);
      expect(validation.ok).toBe(true);
      expect(validation.tileCount).toBe(Object.keys(board).length + 10);
    }
  });

  it('carries a board all the way to the last level, 10 tiles at a time', () => {
    for (let run = 0; run < 10; run++) {
      let board = openingBoard();
      for (let level = 2; level <= 5; level++) {
        const dealt = extendPuzzle(board, BOARD_SIZE, COMMON_WORDS, tilesAddedForLevel(level));
        expect(dealt.letters).toHaveLength(10);
        expect(dealt.solution).not.toBeNull();
        // Play the arrangement and carry on from there, as a player would.
        board = dealt.solution!;
        expect(validateBoard(board, generationDict).ok).toBe(true);
      }
      // 20 up front plus 10 a level for four more levels.
      expect(Object.keys(board)).toHaveLength(60);
    }
  });

  it('deals a standalone batch when there is nothing to grow from', () => {
    const dealt = extendPuzzle({}, BOARD_SIZE, COMMON_WORDS, 10);
    expect(dealt.letters).toHaveLength(10);
    for (const word of dealt.words) expect(generationDict.has(word)).toBe(true);
  });
});
