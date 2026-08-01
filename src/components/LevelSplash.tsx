import { LEVEL_COUNT, levelName, tilesAddedForLevel } from '../game/levels';

interface LevelSplashProps {
  /** The level being announced, or null when nothing is showing. */
  level: number | null;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to name the level just reached, then gets out
 * of the way on its own. Clicking anywhere dismisses it early. The end of the
 * game gets the full-screen summary instead of this card.
 */
export function LevelSplash({ level, onDismiss }: LevelSplashProps) {
  if (level === null) return null;

  return (
    <div className="splash-backdrop" onClick={onDismiss} role="presentation">
      <div className="splash" role="status" aria-live="polite">
        <span className="splash-eyebrow">
          Level {level} of {LEVEL_COUNT}
        </span>
        <span className="splash-name">{levelName(level)}</span>
        <span className="splash-note">
          {level === 1
            ? `${tilesAddedForLevel(level)} tiles`
            : `+${tilesAddedForLevel(level)} tiles`}
        </span>
      </div>
    </div>
  );
}
