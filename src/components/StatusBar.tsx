import type { BoardValidation } from '../game/board';

interface StatusBarProps {
  validation: BoardValidation | null;
  dictionaryReady: boolean;
  dictionaryError: boolean;
  tilesLeft: number;
  won: boolean;
}

export function StatusBar({
  validation,
  dictionaryReady,
  dictionaryError,
  tilesLeft,
  won,
}: StatusBarProps) {
  let tone: 'neutral' | 'bad' | 'good' | 'win' = 'neutral';
  let message: string;

  if (dictionaryError) {
    tone = 'bad';
    message = "Couldn't load the dictionary — refresh the page to try again.";
  } else if (!dictionaryReady) {
    message = 'Loading dictionary…';
  } else if (won) {
    tone = 'win';
    message = '🍌 BANANAS! Every tile placed, every word checks out!';
  } else if (validation === null || validation.tileCount === 0) {
    message = 'Drag tiles from your pile onto the board to build crossing words.';
  } else {
    const problems: string[] = [];
    if (validation.invalidRuns.length > 0) {
      const words = validation.invalidRuns.map((r) => r.word.toUpperCase());
      problems.push(`Not words: ${[...new Set(words)].join(', ')}`);
    }
    if (validation.isolatedTiles.length > 0) {
      const n = validation.isolatedTiles.length;
      problems.push(`${n} tile${n === 1 ? " isn't" : "s aren't"} part of a word`);
    }
    if (!validation.connected) {
      problems.push('All words must connect into one group');
    }
    if (problems.length > 0) {
      tone = 'bad';
      message = problems.join(' · ');
    } else {
      tone = 'good';
      message = `All words check out — ${tilesLeft} tile${tilesLeft === 1 ? '' : 's'} to go!`;
    }
  }

  return (
    <div className={`status status-${tone}`}>
      <span className="status-message">{message}</span>
      {!won && <span className="status-count">{tilesLeft} in pile</span>}
    </div>
  );
}
