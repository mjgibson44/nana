import { LEVEL_COUNT, levelName, tilesAddedForLevel } from '../game/levels';

interface LevelSplashProps {
  /** The level being announced, or null when nothing is showing. */
  level: number | null;
  /** True once every level is done — this is the closing card, not a new level. */
  complete: boolean;
  finalScore: number;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to name the level just reached, then gets out
 * of the way on its own. Clicking anywhere dismisses it early.
 */
export function LevelSplash({ level, complete, finalScore, onDismiss }: LevelSplashProps) {
  if (level === null) return null;

  return (
    <div className="splash-backdrop" onClick={onDismiss} role="presentation">
      <div className="splash" role="status" aria-live="polite">
        {complete ? (
          <>
            <span className="splash-eyebrow">All {LEVEL_COUNT} levels</span>
            <span className="splash-name">🍌 Finished!</span>
            <span className="splash-note">Final score {finalScore}</span>
          </>
        ) : (
          <>
            <span className="splash-eyebrow">
              Level {level} of {LEVEL_COUNT}
            </span>
            <span className="splash-name">{levelName(level)}</span>
            <span className="splash-note">
              {level === 1
                ? `${tilesAddedForLevel(level)} tiles`
                : `+${tilesAddedForLevel(level)} tiles`}
            </span>
          </>
        )}
      </div>
    </div>
  );
}
