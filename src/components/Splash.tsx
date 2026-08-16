import { PACE_NAMES, formatSeconds, type SoloPace } from '../game/modes';

/**
 * What the card is announcing:
 *
 *  - `start`: a game opening — how many tiles and how long to place them.
 *  - `speedup`: Endless turning the screw (bigger batches from here), badged
 *    with the solo pace the game is being played at.
 *  - `battleRound`: a Battle round starting, with its multiplier and drip.
 */
export type Splash =
  | { kind: 'start'; title: string; eyebrow: string; note: string }
  | { kind: 'speedup'; seconds: number; tiles: number; pace: SoloPace }
  | {
      kind: 'battleRound';
      round: number;
      final: boolean;
      multiplier: number;
      dripTiles: number;
    };

interface SplashCardProps {
  /** The card to show, or null when nothing is showing. */
  splash: Splash | null;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to announce something — a game starting,
 * Endless speeding up, or a Battle round turning the screw — then gets out
 * of the way on its own. Clicking anywhere dismisses it early.
 */
export function SplashCard({ splash, onDismiss }: SplashCardProps) {
  if (splash === null) return null;

  const content =
    splash.kind === 'start'
      ? { eyebrow: splash.eyebrow, name: splash.title, note: splash.note }
      : splash.kind === 'speedup'
        ? {
            eyebrow: PACE_NAMES[splash.pace],
            name: 'Speeding up!',
            note: `+${splash.tiles} tiles every ${formatSeconds(splash.seconds)} from here`,
          }
        : {
            eyebrow: 'Battle',
            name: splash.final ? 'Final round!' : `Round ${splash.round}`,
            note:
              `Words hit ×${splash.multiplier} · +${splash.dripTiles} ` +
              `tile${splash.dripTiles === 1 ? '' : 's'} every 20s` +
              (splash.final ? ' · no clock — last one standing' : ''),
          };

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
