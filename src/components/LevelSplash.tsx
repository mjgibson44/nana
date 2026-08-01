import { LEVEL_COUNT, levelName, tilesAddedForLevel } from '../game/levels';
import {
  ENDLESS_INITIAL_SECONDS,
  formatSeconds,
  timedLevelSeconds,
  type GameMode,
} from '../game/modes';

/** What the card is announcing: a level starting, or Endless tightening its clock. */
export type Splash = { kind: 'level'; level: number } | { kind: 'speedup'; seconds: number };

interface LevelSplashProps {
  /** The card to show, or null when nothing is showing. */
  splash: Splash | null;
  mode: GameMode;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to name the level just reached — or, in
 * Endless, to warn that tiles are about to start coming faster — then gets out
 * of the way on its own. Clicking anywhere dismisses it early. The end of the
 * game gets the full-screen summary instead of this card.
 *
 * Modes with a clock say what's on it — the countdown itself waits until this
 * card is gone, so reading it costs nothing.
 */
export function LevelSplash({ splash, mode, onDismiss }: LevelSplashProps) {
  if (splash === null) return null;

  const content =
    splash.kind === 'speedup'
      ? {
          eyebrow: 'Endless mode',
          name: 'Speeding up!',
          note: `New tiles every ${formatSeconds(splash.seconds)} from here`,
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
