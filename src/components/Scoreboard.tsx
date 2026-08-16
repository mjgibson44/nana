import { formatSeconds } from '../game/modes';

/** How close to the tile limit counts as "getting close" — the orange zone. */
const TILES_WARN_MARGIN = 5;

/** One floating "+12"/"−12" riding off a score change, alive until its
 * animation ends. */
export interface ScorePop {
  id: number;
  delta: number;
}

/**
 * Tiles against the limit that ends the game. `label` says which count it is —
 * loose tiles in Endless, the whole pile in a Battle. `warnAt`/`urgentAt` are
 * explicit alarm thresholds: from `warnAt` the count flashes orange, from
 * `urgentAt` red and faster. Without them the count falls back to a steady
 * orange near the limit.
 */
export interface TileGauge {
  label: string;
  loose: number;
  limit: number;
  warnAt?: number;
  urgentAt?: number;
}

/** How loudly the gauge is pleading, in the order it escalates. */
export type TileTone = 'ok' | 'warn' | 'alert' | 'urgent' | 'over';

/**
 * Read a gauge's alarm. Over the limit is red — the count flips to how far
 * over. Below it, the explicit thresholds take over when given: red from
 * `urgentAt`, orange from `warnAt`. Without them (Endless), near the limit is
 * a steady orange. Comfortably under is green either way.
 *
 * Shared with the board, which draws the two loud tones as a border of its
 * own, so the warning and the count can never disagree.
 */
export function tileTone(tiles: TileGauge | null): TileTone {
  if (!tiles) return 'ok';
  if (tiles.loose - tiles.limit > 0) return 'over';
  if (tiles.urgentAt !== undefined && tiles.loose >= tiles.urgentAt) return 'urgent';
  if (tiles.warnAt !== undefined && tiles.loose >= tiles.warnAt) return 'alert';
  if (tiles.warnAt === undefined && tiles.limit - tiles.loose <= TILES_WARN_MARGIN) return 'warn';
  return 'ok';
}

interface ScoreboardProps {
  /**
   * The whole running total: every word on the board right now, plus the
   * bonuses banked along the way.
   */
  score: number;
  /**
   * The tutorial's progress, which takes the score's corner while it runs —
   * there's nothing to win there, and the step in hand is what's worth a
   * glance. Null in the modes that keep score.
   */
  step: { current: number; of: number } | null;
  /** Every tile placed on a valid board — the bonus is already in `score`. */
  bonusEarned: boolean;
  /** What that bonus is worth in the current mode. */
  bonusAmount: number;
  /** The game is over; the score is final. */
  complete: boolean;
  /** The header clock, or null in modes without one. */
  timer: { label: string; seconds: number; urgent: boolean } | null;
  /** Battle: which round the game is in ("1/3", "Final"). Null elsewhere. */
  round: string | null;
  /** Tiles against the limit that ends the game. Null while not in play. */
  tiles: TileGauge | null;
  /** Battle: how much of the field is still standing. A room of piles won't
   * fit the header, so the count stands in for them. Null elsewhere. */
  standing: { alive: number; of: number } | null;
  /** Score changes still floating up beside the total. */
  pops: ScorePop[];
  /** A pop's animation finished; it can be dropped. */
  onPopEnd: (id: number) => void;
}

export function Scoreboard({
  score,
  step,
  bonusEarned,
  bonusAmount,
  complete,
  timer,
  round,
  tiles,
  standing,
  pops,
  onPopEnd,
}: ScoreboardProps) {
  // How far past the limit the count has gone, which is what it shows once
  // it's over one. The colour it shows in is tileTone's business.
  const over = tiles ? tiles.loose - tiles.limit : 0;
  const tilesTone = tileTone(tiles);

  return (
    <div className="scoreboard">
      {step ? (
        <div className="score-block">
          <span className="score-label">Step</span>
          {/* Keyed like the score, so stepping forward gets the same bump. */}
          <span key={step.current} className="score-value score-value-points">
            {step.current}
            <span className="score-of"> of {step.of}</span>
          </span>
        </div>
      ) : (
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
      )}
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
      {standing && (
        <div
          className="score-block"
          title={`${standing.alive} of ${standing.of} players still standing`}
        >
          <span className="score-label">Standing</span>
          <span className="score-value">
            {standing.alive}
            <span className="score-of"> of {standing.of}</span>
          </span>
        </div>
      )}
      {bonusEarned && (
        <span className="score-chip score-chip-bonus">+{bonusAmount} all tiles</span>
      )}
    </div>
  );
}
