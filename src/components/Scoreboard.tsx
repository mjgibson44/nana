import { ordinal } from '../game/battle';
import { formatSeconds } from '../game/modes';

/** How close to the tile limit counts as "getting close" — the orange zone. */
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
   * bonuses banked along the way.
   */
  score: number;
  /** Every tile placed on a valid board — the bonus is already in `score`. */
  bonusEarned: boolean;
  /** What that bonus is worth in the current mode. */
  bonusAmount: number;
  /** The game is over; the score is final. */
  complete: boolean;
  /** The header clock, or null in modes without one. */
  timer: { label: string; seconds: number; urgent: boolean } | null;
  /** Duel: which round the game is in ("1/3", "Final"). Null elsewhere. */
  round: string | null;
  /** Tiles against the limit that ends the game. Null while not in play.
   * `label` says which count it is — loose tiles in Endless, the whole
   * pile in a Duel. */
  tiles: { label: string; loose: number; limit: number } | null;
  /** Duel: the other player's pile, to watch them drown (or not). */
  opponent: { name: string; tiles: number; limit: number; out: boolean } | null;
  /** This player's place in a battle, or null outside one. */
  rank: { place: number; of: number; buried: boolean } | null;
  /** Score changes still floating up beside the total. */
  pops: ScorePop[];
  /** A pop's animation finished; it can be dropped. */
  onPopEnd: (id: number) => void;
}

export function Scoreboard({
  score,
  bonusEarned,
  bonusAmount,
  complete,
  timer,
  round,
  tiles,
  opponent,
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
      {round !== null && (
        <div className="score-block">
          <span className="score-label">Round</span>
          <span className="score-value">{round}</span>
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
              ? `${tiles.loose} tiles — ${over} over the limit of ${tiles.limit}.`
              : `${tiles.loose} of ${tiles.limit} tiles against the limit`
          }
        >
          <span className="score-label">{over > 0 ? 'Limit exceeded' : tiles.label}</span>
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
      {opponent && (
        <div
          className="score-block"
          title={`${opponent.name}’s pile: ${opponent.tiles} of ${opponent.limit} tiles`}
        >
          <span className="score-label">{opponent.name}</span>
          <span className="score-value">
            {opponent.out ? (
              '💀'
            ) : (
              <>
                {opponent.tiles}
                <span className="score-of">/{opponent.limit}</span>
              </>
            )}
          </span>
        </div>
      )}
      {bonusEarned && (
        <span className="score-chip score-chip-bonus">+{bonusAmount} all tiles</span>
      )}
    </div>
  );
}
