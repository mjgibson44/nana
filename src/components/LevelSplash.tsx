import { LEVEL_COUNT, levelName, tilesAddedForLevel } from '../game/levels';
import {
  ENDLESS_INITIAL_SECONDS,
  formatSeconds,
  timedLevelSeconds,
  type GameMode,
} from '../game/modes';

interface LevelSplashProps {
  /** The level being announced, or null when nothing is showing. */
  level: number | null;
  mode: GameMode;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to name the level just reached, then gets out
 * of the way on its own. Clicking anywhere dismisses it early. The end of the
 * game gets the full-screen summary instead of this card.
 *
 * Modes with a clock say what's on it — the countdown itself waits until this
 * card is gone, so reading it costs nothing.
 */
export function LevelSplash({ level, mode, onDismiss }: LevelSplashProps) {
  if (level === null) return null;

  const tiles =
    level === 1 ? `${tilesAddedForLevel(level)} tiles` : `+${tilesAddedForLevel(level)} tiles`;

  const eyebrow = mode === 'endless' ? 'Endless mode' : `Level ${level} of ${LEVEL_COUNT}`;
  const name = mode === 'endless' ? 'Go bananas!' : levelName(level);
  const note =
    mode === 'timed'
      ? `${tiles} · ${formatSeconds(timedLevelSeconds(level))} on the clock`
      : mode === 'endless'
        ? `${tiles} · ${formatSeconds(ENDLESS_INITIAL_SECONDS)} to place them`
        : tiles;

  return (
    <div className="splash-backdrop" onClick={onDismiss} role="presentation">
      <div className="splash" role="status" aria-live="polite">
        <span className="splash-eyebrow">{eyebrow}</span>
        <span className="splash-name">{name}</span>
        <span className="splash-note">{note}</span>
      </div>
    </div>
  );
}
