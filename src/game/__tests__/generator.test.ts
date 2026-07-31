import { describe, expect, it } from 'vitest';
import { validateBoard } from '../board';
import { COMMON_WORDS } from '../commonWords';
import { generatePuzzle } from '../generator';

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
