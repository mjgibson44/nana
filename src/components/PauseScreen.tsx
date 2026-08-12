import { useEffect } from 'react';
import { PauseIcon } from './icons';

interface PauseScreenProps {
  /** False while the game is running — nothing renders. */
  open: boolean;
  /** What's on hold, in the words the start splash used — "Blitz · Fast",
   * "Puzzle Solve". */
  eyebrow: string;
  /** Back to the board, with every clock picking up where it stopped. */
  onResume: () => void;
}

/**
 * The pause screen: a whole window, not a card.
 *
 * A paused game in a mode with a clock is a game whose pressure is off, so it
 * can't leave the board readable — a player who could still see their pile
 * and plan against a stopped clock would only be cheating themselves out of
 * the mode they picked. So this covers the lot, opaquely, and the one way
 * back is the button (or Escape, which every other overlay here answers to).
 */
export function PauseScreen({ open, eyebrow, onResume }: PauseScreenProps) {
  useEffect(() => {
    if (!open) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onResume();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [open, onResume]);

  if (!open) return null;

  return (
    <div className="pause-screen" role="dialog" aria-modal="true" aria-label="Paused">
      <div className="pause-inner">
        <span className="pause-mark" aria-hidden="true">
          <PauseIcon size={34} />
        </span>
        <span className="splash-eyebrow">{eyebrow}</span>
        <h1 className="pause-title">Paused</h1>
        <p className="pause-note">
          Every clock is stopped and the board is put away until you&rsquo;re back.
        </p>
        <button type="button" className="btn btn-primary pause-resume" onClick={onResume} autoFocus>
          Resume
        </button>
      </div>
    </div>
  );
}
