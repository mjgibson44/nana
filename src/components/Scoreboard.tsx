import { ALL_TILES_BONUS, LEVEL_COUNT } from '../game/levels';

/** One floating "+12"/"−12" riding off a score change, alive until its
 * animation ends. */
export interface ScorePop {
  id: number;
  delta: number;
}

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
  /** Score changes still floating up beside the total. */
  pops: ScorePop[];
  /** A pop's animation finished; it can be dropped. */
  onPopEnd: (id: number) => void;
}

export function Scoreboard({
  score,
  level,
  bonusEarned,
  complete,
  pops,
  onPopEnd,
}: ScoreboardProps) {
  return (
    <div className="scoreboard">
      <div className="score-block score-block-points">
        <span className="score-label">{complete ? 'Final score' : 'Score'}</span>
        {/* Keyed by value so every change replays the little bump. */}
        <span key={score} className="score-value score-value-points">
          {score}
        </span>
        {/* Decoration only — the score itself already reads the new total. */}
        <div className="score-pops" aria-hidden="true">
          {pops.map((pop) => (
            <span
              key={pop.id}
              className={`score-pop ${pop.delta > 0 ? 'score-pop-gain' : 'score-pop-loss'}`}
              onAnimationEnd={() => onPopEnd(pop.id)}
            >
              {pop.delta > 0 ? `+${pop.delta}` : `−${-pop.delta}`}
            </span>
          ))}
        </div>
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
