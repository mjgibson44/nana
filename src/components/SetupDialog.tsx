import { CloseIcon } from './icons';

export interface SetupSetting {
  /** What's being set ("Game style", "Grid size", "Speed"). */
  label: string;
  /** What the tabs say ("Solve", "Flow"). Kept short — they're tabs; what each
   * one means belongs to the mode's explainer, not to a sheet being skimmed on
   * the way past. */
  options: readonly string[];
  /** Which option is chosen, by index into `options`. */
  chosen: number;
  onChoose: (index: number) => void;
}

interface SetupDialogProps {
  /** The mode being set up ("Solo"). */
  title: string;
  /** One row per setting, in the order they're asked. */
  settings: readonly SetupSetting[];
  /** Start the game the settings describe. */
  onPlay: () => void;
  /** Walk away without starting anything — also what the corner X and a click
   * on the backdrop do. */
  onDismiss: () => void;
}

/**
 * The setup sheet a configurable mode raises on the way in: every setting the
 * mode has, one row each, and a Play button under the lot. A mode with several
 * settings asks for them together rather than one popup after another, and
 * nothing is decided until Play — so a setting can be changed back, and the X
 * (or a click outside) backs out of the mode altogether.
 */
export function SetupDialog({ title, settings, onPlay, onDismiss }: SetupDialogProps) {
  return (
    <div className="splash-backdrop" onClick={onDismiss} role="presentation">
      <div
        className="dialog mode-info"
        role="dialog"
        aria-modal="true"
        aria-label={`${title} — set up your game`}
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
        <span className="mode-card-tagline">Set up your game</span>
        <div className="setup-settings">
          {settings.map((setting) => (
            <div className="setup-setting" key={setting.label}>
              <span className="setup-setting-label">{setting.label}</span>
              <div className="setup-tabs" role="radiogroup" aria-label={setting.label}>
                {setting.options.map((option, index) => (
                  <button
                    key={option}
                    type="button"
                    role="radio"
                    aria-checked={index === setting.chosen}
                    className={`setup-tab${index === setting.chosen ? ' is-active' : ''}`}
                    onClick={() => setting.onChoose(index)}
                  >
                    {option}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
        <div className="dialog-actions">
          <button type="button" className="btn btn-primary" onClick={onPlay}>
            Play
          </button>
        </div>
      </div>
    </div>
  );
}
