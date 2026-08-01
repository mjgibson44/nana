import { useMemo } from 'react';

/** One scored word from the finished board. */
export interface ScoredWord {
  word: string;
  points: number;
}

interface GameSummaryProps {
  /** Null while the game is still going — nothing renders. */
  words: ScoredWord[] | null;
  score: number;
  onPlayAgain: () => void;
  onClose: () => void;
}

/**
 * The end-of-game report card. Fills the whole screen: the score and word
 * count up top, then how the words broke down by length, then every word
 * with what it was worth.
 */
export function GameSummary({ words, score, onPlayAgain, onClose }: GameSummaryProps) {
  // Longest first: the lengths that earned the most, and within the word list
  // the proudest words at the top.
  const byLength = useMemo(() => {
    if (!words) return [];
    const counts = new Map<number, number>();
    for (const { word } of words) {
      counts.set(word.length, (counts.get(word.length) ?? 0) + 1);
    }
    return [...counts.entries()].sort((a, b) => b[0] - a[0]);
  }, [words]);

  const sortedWords = useMemo(
    () =>
      words
        ? [...words].sort((a, b) => b.points - a.points || a.word.localeCompare(b.word))
        : [],
    [words],
  );

  if (!words) return null;

  return (
    <div className="summary" role="dialog" aria-modal="true" aria-label="Game finished">
      <div className="summary-inner">
        <header className="summary-header">
          <span className="splash-eyebrow">Game finished</span>
          <h1 className="summary-title">🍌 Well played!</h1>
        </header>

        <div className="summary-totals">
          <div className="summary-stat">
            <span className="summary-stat-value">{score}</span>
            <span className="summary-stat-label">Final score</span>
          </div>
          <div className="summary-stat">
            <span className="summary-stat-value">{words.length}</span>
            <span className="summary-stat-label">{words.length === 1 ? 'Word' : 'Words'}</span>
          </div>
        </div>

        {byLength.length > 0 && (
          <section className="summary-section">
            <h2 className="summary-section-title">By length</h2>
            <ul className="summary-lengths">
              {byLength.map(([length, count]) => (
                <li key={length} className="summary-length">
                  <span className="summary-length-count">{count}×</span> {length}-letter
                </li>
              ))}
            </ul>
          </section>
        )}

        <section className="summary-section">
          <h2 className="summary-section-title">Your words</h2>
          <ul className="summary-words">
            {sortedWords.map(({ word, points }, i) => (
              // The same word can be on the board twice, so the key needs the
              // position too.
              // eslint-disable-next-line react/no-array-index-key
              <li key={`${word}-${i}`} className="summary-word">
                <span className="summary-word-text">{word.toUpperCase()}</span>
                <span className="summary-word-points">+{points}</span>
              </li>
            ))}
          </ul>
        </section>

        <div className="summary-actions">
          <button type="button" className="btn btn-primary" onClick={onPlayAgain}>
            Play again
          </button>
          <button type="button" className="btn" onClick={onClose}>
            See the board
          </button>
        </div>
      </div>
    </div>
  );
}
