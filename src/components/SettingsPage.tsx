import type { ThemePref } from '../theme';
import { CloseIcon } from './icons';

interface SettingsPageProps {
  /** False while the page is closed — nothing renders. */
  open: boolean;
  theme: ThemePref;
  onTheme: (pref: ThemePref) => void;
  /** Whether the game's sound effects play. */
  sound: boolean;
  onSound: (on: boolean) => void;
  onClose: () => void;
}

const THEME_OPTIONS: Array<{ value: ThemePref; label: string; detail: string }> = [
  { value: 'light', label: 'Light', detail: 'Bright board, dark letters' },
  { value: 'dark', label: 'Dark', detail: 'Dark board, light letters' },
  { value: 'system', label: 'System', detail: 'Follow your device' },
];

/**
 * The settings page, reached from the menu in the top-right corner of a game
 * or from the home screen. Holds the theme choice and the sound switch;
 * anything else the game grows a preference for lands here too.
 */
export function SettingsPage({
  open,
  theme,
  onTheme,
  sound,
  onSound,
  onClose,
}: SettingsPageProps) {
  if (!open) return null;

  return (
    <div className="summary" role="dialog" aria-modal="true" aria-label="Settings">
      <button
        type="button"
        className="icon-btn page-close"
        onClick={onClose}
        title="Close"
        aria-label="Close"
      >
        <CloseIcon />
      </button>

      <div className="summary-inner">
        <header className="summary-header">
          <span className="splash-eyebrow">Options</span>
          <h1 className="summary-title">Settings</h1>
        </header>

        <section className="summary-section">
          <h2 className="summary-section-title">Appearance</h2>
          <div className="settings-options" role="radiogroup" aria-label="Theme">
            {THEME_OPTIONS.map((option) => (
              <button
                key={option.value}
                type="button"
                role="radio"
                aria-checked={theme === option.value}
                className={`settings-option${theme === option.value ? ' is-active' : ''}`}
                onClick={() => onTheme(option.value)}
              >
                <span className="settings-option-label">{option.label}</span>
                <span className="settings-option-detail">{option.detail}</span>
              </button>
            ))}
          </div>
        </section>

        <section className="summary-section">
          <h2 className="summary-section-title">Audio</h2>
          <button
            type="button"
            role="switch"
            aria-checked={sound}
            className={`settings-toggle${sound ? ' is-on' : ''}`}
            onClick={() => onSound(!sound)}
          >
            <span className="settings-toggle-text">
              <span className="settings-option-label">Game sound</span>
              <span className="settings-option-detail">
                Countdown ticks, tiles landing, words going down
              </span>
            </span>
            <span className="settings-switch" aria-hidden="true">
              <span className="settings-switch-knob" />
            </span>
          </button>
        </section>

        <div className="summary-actions">
          <button type="button" className="btn btn-primary" onClick={onClose}>
            Done
          </button>
        </div>
      </div>
    </div>
  );
}
