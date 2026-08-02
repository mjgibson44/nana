import { ordinal } from '../game/battle';
import { LEVEL_COUNT } from '../game/levels';
import { formatSeconds } from '../game/modes';

/** How close to the loose limit counts as "getting close" — the orange zone. */
const TILES_WARN_MARGIN = 5;

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
  /** Endless: how many tiles are loose against the limit that buries the
   * player at a round's end. Null while the count isn't in play. */
  tiles: { loose: number; limit: number } | null;
  /** This player's place in a battle, or null outside one. */
  rank: { place: number; of: number; buried: boolean } | null;
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
  tiles,
  rank,
  pops,
  onPopEnd,
}: ScoreboardProps) {
  // Over the limit is red — the count flips to how far over. At or near the
  // limit is orange; comfortably under is green.
  const over = tiles ? tiles.loose - tiles.limit : 0;
  const tilesTone =
    over > 0 ? 'over' : tiles && tiles.limit - tiles.loose <= TILES_WARN_MARGIN ? 'warn' : 'ok';

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
      {rank && (
        <div className="score-block" title={`Your place among ${rank.of} players`}>
          <span className="score-label">Position</span>
          <span className="score-value">
            {rank.buried && '💀 '}
            {ordinal(rank.place)}
            <span className="score-of"> of {rank.of}</span>
          </span>
        </div>
      )}
      {tiles && (
        <div
          className="score-block"
          title={
            over > 0
              ? `${tiles.loose} loose tiles — ${over} over the limit of ${tiles.limit}. ` +
                `Get back under before the round ends or you're buried.`
              : `${tiles.loose} of ${tiles.limit} loose tiles — end a round over the limit ` +
                `and you're buried`
          }
        >
          <span className="score-label">{over > 0 ? 'Limit exceeded' : 'Loose tiles'}</span>
          <span className={`score-value tile-count-${tilesTone}`}>
            {over > 0 ? (
              `+${over}`
            ) : (
              <>
                {tiles.loose}
                <span className="score-of">/{tiles.limit}</span>
              </>
            )}
          </span>
        </div>
      )}
      {bonusEarned && (
        <span className="score-chip score-chip-bonus">🍌 +{bonusAmount} all tiles</span>
      )}
    </div>
  );
}
