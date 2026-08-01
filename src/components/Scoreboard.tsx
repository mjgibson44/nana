import { LEVEL_COUNT } from '../game/levels';
import { formatSeconds } from '../game/modes';

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
  /** The current level, or null in modes without levels (Endless). */
  level: number | null;
  /** Every tile placed on a valid board — the bonus is already in `score`. */
  bonusEarned: boolean;
  /** What that bonus is worth in the current mode. */
  bonusAmount: number;
  /** The game is over; the score is final. */
  complete: boolean;
  /** The header clock, or null in modes without one. */
  timer: { label: string; seconds: number; urgent: boolean } | null;
  /** Endless health: how many tiles are loose against the limit that ends the
   * game. Null while the bar isn't in play. */
  health: { loose: number; limit: number } | null;
  /** Score changes still floating up beside the total. */
  pops: ScorePop[];
  /** A pop's animation finished; it can be dropped. */
  onPopEnd: (id: number) => void;
}

export function Scoreboard({
  score,
  level,
  bonusEarned,
  bonusAmount,
  complete,
  timer,
  health,
  pops,
  onPopEnd,
}: ScoreboardProps) {
  // The bar shows health draining as loose tiles pile up toward the limit.
  const healthLeft = health ? Math.max(0, health.limit - health.loose) : 0;
  const healthFraction = health ? healthLeft / health.limit : 0;
  const healthTone = healthFraction > 0.5 ? 'ok' : healthFraction > 0.25 ? 'warn' : 'low';

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
      {level !== null && (
        <div className="score-block">
          <span className="score-label">Level</span>
          <span className="score-value">
            {complete ? 'Done' : level}
            {!complete && <span className="score-of">/{LEVEL_COUNT}</span>}
          </span>
        </div>
      )}
      {timer && (
        <div className="score-block">
          <span className="score-label">{timer.label}</span>
          <span className={`score-value score-timer${timer.urgent ? ' score-timer-urgent' : ''}`}>
            {formatSeconds(timer.seconds)}
          </span>
        </div>
      )}
      {health && (
        <div
          className="score-block score-block-health"
          title={`${health.loose} of ${health.limit} loose tiles — reach ${health.limit} and the game is over`}
        >
          <span className="score-label">Health</span>
          <div
            className="health-bar"
            role="meter"
            aria-label="Health"
            aria-valuemin={0}
            aria-valuemax={health.limit}
            aria-valuenow={healthLeft}
          >
            <div
              className={`health-fill health-${healthTone}`}
              style={{ width: `${healthFraction * 100}%` }}
            />
          </div>
          <span className="health-count">
            {health.loose}/{health.limit} loose
          </span>
        </div>
      )}
      {bonusEarned && (
        <span className="score-chip score-chip-bonus">🍌 +{bonusAmount} all tiles</span>
      )}
    </div>
  );
}
