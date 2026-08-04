import { CloseIcon } from './icons';

export interface ChoiceOption {
  label: string;
  detail: string;
}

interface ChoiceDialogProps {
  /** The mode being configured ("Blitz", "Puzzle"). */
  title: string;
  /** What's being chosen ("Pick your pace"). */
  subtitle: string;
  options: readonly ChoiceOption[];
  onPick: (index: number) => void;
  /** Walk away without starting anything — also what the corner X and a click
   * on the backdrop do. */
  onDismiss: () => void;
}

/**
 * The popup a configurable mode raises on the way in: Blitz asking which
 * pace, Puzzle asking which board. One tap on an option starts the game;
 * the X, or a click outside, backs out of the mode altogether.
 */
export function ChoiceDialog({ title, subtitle, options, onPick, onDismiss }: ChoiceDialogProps) {
  return (
    <div className="splash-backdrop" onClick={onDismiss} role="presentation">
      <div
        className="dialog mode-info"
        role="dialog"
        aria-modal="true"
        aria-label={`${title} — ${subtitle}`}
        // Clicking inside shouldn't count as clicking the backdrop away.
        onClick={(e) => e.stopPropagation()}
      >
        <button
          type="button"
          className="icon-btn dialog-close"
          onClick={onDismiss}
          title="Close"
          aria-label="Close"
        >
          <CloseIcon />
        </button>
        <span className="mode-card-name">{title}</span>
        <span className="mode-card-tagline">{subtitle}</span>
        <div className="choice-options">
          {options.map((option, index) => (
            <button
              key={option.label}
              type="button"
              className="choice-option"
              onClick={() => onPick(index)}
            >
              <span className="choice-option-name">{option.label}</span>
              <span className="choice-option-detail">{option.detail}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
