import { SOLO_INFO, formatSeconds, type SoloPace } from '../game/modes';

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
 * What the card is announcing:
 *
 *  - `start`: a game opening — how many tiles and how long to place them.
 *  - `speedup`: Endless turning the screw (bigger batches from here), badged
 *    with the solo pace the game is being played at.
 *  - `round`: an Endless Battle round ending, with the whole field's scores.
 *  - `duelRound`: a Duel round starting, with its multiplier and drip.
 */
export type Splash =
  | { kind: 'start'; title: string; eyebrow: string; note: string }
  | { kind: 'speedup'; seconds: number; tiles: number; pace: SoloPace }
  | { kind: 'round'; standings: RoundStanding[]; seconds: number; tiles: number }
  | { kind: 'duelRound'; round: number; final: boolean; multiplier: number; dripTiles: number };

interface SplashCardProps {
  /** The card to show, or null when nothing is showing. */
  splash: Splash | null;
  onDismiss: () => void;
}

/**
 * A card that pops over the board to announce something — a game starting,
 * Endless speeding up, a Duel round turning the screw, or a battle round
 * ending with the whole field's scores — then gets out of the way on its
 * own. Clicking anywhere dismisses it early.
 */
export function SplashCard({ splash, onDismiss }: SplashCardProps) {
  if (splash === null) return null;

  if (splash.kind === 'round') {
    return (
      <div className="splash-backdrop" onClick={onDismiss} role="presentation">
        <div className="splash splash-round" role="status" aria-live="polite">
          <span className="splash-eyebrow">Survival</span>
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
    splash.kind === 'start'
      ? { eyebrow: splash.eyebrow, name: splash.title, note: splash.note }
      : splash.kind === 'speedup'
        ? {
            eyebrow: SOLO_INFO[splash.pace].name,
            name: 'Speeding up!',
            note: `+${splash.tiles} tiles every ${formatSeconds(splash.seconds)} from here`,
          }
        : {
            eyebrow: 'Duel',
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
