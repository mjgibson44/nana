import { ALL_TILES_BONUS, LEVEL_COUNT } from '../game/levels';

interface ScoreboardProps {
  /**
   * The whole running total: every word on the board right now, plus the
   * all-tiles bonuses banked from levels already finished.
   */
  score: number;
  level: number;
  /** Every tile placed on a valid board — the bonus is already in `score`. */
  bonusEarned: boolean;
  /** All levels finished; the score is final. */
  complete: boolean;
}

export function Scoreboard({ score, level, bonusEarned, complete }: ScoreboardProps) {
  return (
    <div className="scoreboard">
      <div className="score-block">
        <span className="score-label">{complete ? 'Final score' : 'Score'}</span>
        <span className="score-value">{score}</span>
      </div>
      <div className="score-block">
        <span className="score-label">Level</span>
        <span className="score-value">
          {complete ? 'Done' : level}
          {!complete && <span className="score-of">/{LEVEL_COUNT}</span>}
        </span>
      </div>
      {bonusEarned && (
        <span className="score-chip score-chip-bonus">🍌 +{ALL_TILES_BONUS} all tiles</span>
      )}
    </div>
  );
}
