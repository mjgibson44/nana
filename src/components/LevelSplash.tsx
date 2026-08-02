import { LEVEL_COUNT, levelName, tilesAddedForLevel } from '../game/levels';
import {
  ENDLESS_INITIAL_SECONDS,
  formatSeconds,
  timedLevelSeconds,
  type GameMode,
} from '../game/modes';

/** One line of the between-rounds battle scoreboard. */
export interface RoundStanding {
  rank: number;
  name: string;
  score: number;
  self: boolean;
  /** Buried or gone — out of the running either way. */
  buried: boolean;
}

/**
 * What the card is announcing: a level starting, Endless turning the screw
 * (a faster clock or bigger batches), or a battle round ending with the
 * whole field's scores. `seconds` is the new round length and `tiles` the
 * batch size it lands with.
 */
export type Splash =
  | { kind: 'level'; level: number }
  | { kind: 'speedup'; seconds: number; tiles: number }
  | { kind: 'round'; standings: RoundStanding[]; seconds: number; tiles: number };

interface LevelSplashProps {
  /** The card to show, or null when nothing is showing. */
  splash: Splash | null;
  mode: GameMode;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to name the level just reached — or, in
 * Endless, to warn that tiles are about to start coming faster, or between
 * battle rounds to show where everyone stands — then gets out of the way on
 * its own. Clicking anywhere dismisses it early. The end of the game gets the
 * full-screen summary instead of this card.
 *
 * Solo modes with a clock say what's on it — the countdown itself waits until
 * this card is gone, so reading it costs nothing. A battle's shared clock
 * keeps running behind the card, which is why the round card dismisses on a
 * tap anywhere.
 */
export function LevelSplash({ splash, mode, onDismiss }: LevelSplashProps) {
  if (splash === null) return null;

  if (splash.kind === 'round') {
    return (
      <div className="splash-backdrop" onClick={onDismiss} role="presentation">
        <div className="splash splash-round" role="status" aria-live="polite">
          <span className="splash-eyebrow">Endless battle</span>
          <span className="splash-name">Round over!</span>
          <ol className="splash-standings">
            {splash.standings.map((standing, i) => (
              <li
                // eslint-disable-next-line react/no-array-index-key
                key={i}
                className={
                  'splash-standing' +
                  (standing.self ? ' splash-standing-self' : '') +
                  (standing.buried ? ' splash-standing-buried' : '')
                }
              >
                <span className="splash-standing-place">{standing.rank}</span>
                <span className="splash-standing-name">
                  {standing.name}
                  {standing.buried && ' 💀'}
                </span>
                <span className="splash-standing-score">{standing.score}</span>
              </li>
            ))}
          </ol>
          <span className="splash-note">
            +{splash.tiles} tiles · next batch in {formatSeconds(splash.seconds)}
          </span>
        </div>
      </div>
    );
  }

  const content =
    splash.kind === 'speedup'
      ? {
          eyebrow: 'Endless mode',
          name: 'Speeding up!',
          note: `+${splash.tiles} tiles every ${formatSeconds(splash.seconds)} from here`,
        }
      : levelContent(splash.level, mode);

  return (
    <div className="splash-backdrop" onClick={onDismiss} role="presentation">
      <div className="splash" role="status" aria-live="polite">
        <span className="splash-eyebrow">{content.eyebrow}</span>
        <span className="splash-name">{content.name}</span>
        <span className="splash-note">{content.note}</span>
      </div>
    </div>
  );
}

function levelContent(level: number, mode: GameMode) {
  const tiles =
    level === 1 ? `${tilesAddedForLevel(level)} tiles` : `+${tilesAddedForLevel(level)} tiles`;

  return {
    eyebrow: mode === 'endless' ? 'Endless mode' : `Level ${level} of ${LEVEL_COUNT}`,
    name: mode === 'endless' ? 'Go bananas!' : levelName(level),
    note:
      mode === 'timed'
        ? `${tiles} · ${formatSeconds(timedLevelSeconds(level))} on the clock`
        : mode === 'endless'
          ? `${tiles} · ${formatSeconds(ENDLESS_INITIAL_SECONDS)} to place them`
          : tiles,
  };
}
