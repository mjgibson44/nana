import type { ModeInfo } from '../game/modes';

interface ModeInfoDialogProps {
  /** The mode being introduced, or null while nothing is up. */
  info: ModeInfo | null;
  /** Read it and carry on into the game. Clicking the backdrop does the same —
   * there is nothing to go back to, so every way out of this leads forward. */
  onPlay: () => void;
}

/**
 * What a mode is, shown once: the first time a player opens each door, this
 * stands between the choice and the game. It's the only place the rules of a
 * mode are spelled out, so it says its piece and then gets out of the way for
 * good.
 */
export function ModeInfoDialog({ info, onPlay }: ModeInfoDialogProps) {
  if (info === null) return null;

  return (
    <div className="splash-backdrop" onClick={onPlay} role="presentation">
      <div
        className="dialog mode-info"
        role="dialog"
        aria-modal="true"
        aria-label={`About ${info.name}`}
        // Clicking inside shouldn't count as clicking the backdrop away.
        onClick={(e) => e.stopPropagation()}
      >
        <span className="mode-card-name">{info.name}</span>
        <span className="mode-card-tagline">{info.tagline}</span>
        <span className="mode-card-details">
          {info.details.map((detail) => (
            <span key={detail} className="mode-card-detail">
              {detail}
            </span>
          ))}
        </span>
        <div className="dialog-actions">
          <button type="button" className="btn btn-primary" onClick={onPlay}>
            Let’s play
          </button>
        </div>
      </div>
    </div>
  );
}
