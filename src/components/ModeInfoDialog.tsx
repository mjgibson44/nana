import type { ModeInfo } from '../game/modes';
import { CloseIcon } from './icons';

interface ModeInfoDialogProps {
  /** The mode being introduced, or null while nothing is up. */
  info: ModeInfo | null;
  /** The label on the button that carries on into what this introduces. */
  confirmLabel: string;
  onConfirm: () => void;
  /**
   * A way past the thing being introduced, for the cards that have somewhere
   * to be instead — the tutorial's does, a mode's own card doesn't. It's also
   * what the corner X and a click on the backdrop do; without it every way out
   * leads forward, since there's nothing behind a card that only says what you
   * chose.
   */
  skipLabel?: string;
  onSkip?: () => void;
}

/**
 * A mode's card, standing between choosing it and playing it: what it is, and
 * its three headline rules. Each is shown once ever — a mode's the first time
 * its door is opened, the tutorial's before a player's first game — so it says
 * its piece and then gets out of the way for good.
 */
export function ModeInfoDialog({
  info,
  confirmLabel,
  onConfirm,
  skipLabel,
  onSkip,
}: ModeInfoDialogProps) {
  if (info === null) return null;

  const dismiss = onSkip ?? onConfirm;

  return (
    <div className="splash-backdrop" onClick={dismiss} role="presentation">
      <div
        className="dialog mode-info"
        role="dialog"
        aria-modal="true"
        aria-label={`About ${info.name}`}
        // Clicking inside shouldn't count as clicking the backdrop away.
        onClick={(e) => e.stopPropagation()}
      >
        <button
          type="button"
          className="icon-btn dialog-close"
          onClick={dismiss}
          title="Close"
          aria-label="Close"
        >
          <CloseIcon />
        </button>
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
          {/* A plain button, not the red back-out one: passing on an offer is
              not the same kind of act as abandoning a game. */}
          {skipLabel !== undefined && (
            <button type="button" className="btn" onClick={onSkip}>
              {skipLabel}
            </button>
          )}
          <button type="button" className="btn btn-primary" onClick={onConfirm}>
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
