import { useState } from 'react';
import { CODE_LENGTH, isValidBattleCode, normalizeBattleCode, type BattleMode } from '../game/battle';

interface BattleMenuProps {
  /** Which game hosting from here opens: an Endless Battle or a Duel. */
  mode: BattleMode;
  /** The player name last used on this device, to save retyping. */
  initialName: string;
  /** A code carried in by a share link, ready to join. */
  initialCode: string;
  /** What the app is busy doing ("Opening a lobby…"), or null when idle. */
  busy: string | null;
  /** Why the last attempt failed, or null. */
  error: string | null;
  onHost: (name: string) => void;
  onJoin: (name: string, code: string) => void;
  onBack: () => void;
}

const COPY: Record<BattleMode, { title: string; tagline: string; host: string }> = {
  endless: {
    title: 'Survival',
    tagline:
      'Everyone digs out of the same tiles — the last board standing, or the highest score, takes it.',
    host: 'Host a game',
  },
  duel: {
    title: 'Duel',
    tagline:
      'Two players, the same tiles. Placed words are permanent — and every word sends tiles to your opponent. Overflow your pile and you lose.',
    host: 'Host a duel',
  },
  battle: {
    title: 'Battle',
    tagline:
      'Up to eight players, the same tiles. Placed words are permanent — and every word scatters tiles across your rivals. Overflow your pile and you’re out; the last one standing wins.',
    host: 'Host a battle',
  },
};

/**
 * The multiplayer doorway: give a name, then either open a lobby or enter a
 * friend's code. Arriving by share link lands here with the code filled in,
 * so joining is just confirming a name. (Joining works for either mode —
 * the code decides what game you land in.)
 */
export function BattleMenu({
  mode,
  initialName,
  initialCode,
  busy,
  error,
  onHost,
  onJoin,
  onBack,
}: BattleMenuProps) {
  const [name, setName] = useState(initialName);
  const [code, setCode] = useState(initialCode);

  const trimmedName = name.trim();
  const codeReady = isValidBattleCode(normalizeBattleCode(code));
  const disabled = busy !== null;
  const copy = COPY[mode];

  const join = () => {
    if (trimmedName && codeReady) onJoin(trimmedName, normalizeBattleCode(code));
  };

  return (
    <div className="home">
      <div className="home-inner battle-inner">
        <header className="home-header">
          <h1 className="home-title">{copy.title}</h1>
          <p className="home-tagline">{copy.tagline}</p>
        </header>

        <div className="battle-card">
          <label className="battle-field">
            <span className="battle-label">Your name</span>
            <input
              className="battle-input"
              type="text"
              value={name}
              maxLength={24}
              placeholder="e.g. Alex"
              autoFocus={initialCode === ''}
              disabled={disabled}
              onChange={(e) => setName(e.target.value)}
            />
          </label>

          <button
            type="button"
            className="btn btn-primary battle-wide-btn"
            disabled={disabled || trimmedName === ''}
            onClick={() => onHost(trimmedName)}
          >
            {copy.host}
          </button>

          <div className="battle-divider">
            <span>or join a friend</span>
          </div>

          <label className="battle-field">
            <span className="battle-label">Game code</span>
            <input
              className="battle-input battle-code-input"
              type="text"
              value={code}
              maxLength={CODE_LENGTH + 2}
              placeholder={'·'.repeat(CODE_LENGTH)}
              autoFocus={initialCode !== ''}
              disabled={disabled}
              onChange={(e) => setCode(normalizeBattleCode(e.target.value))}
              onKeyDown={(e) => {
                if (e.key === 'Enter') join();
              }}
            />
          </label>

          <button
            type="button"
            className="btn btn-primary battle-wide-btn"
            disabled={disabled || trimmedName === '' || !codeReady}
            onClick={join}
          >
            Join with this code
          </button>

          {busy && <p className="battle-status" role="status">{busy}</p>}
          {error && !busy && <p className="battle-error" role="alert">{error}</p>}
        </div>

        <div className="home-actions">
          <button type="button" className="btn" disabled={disabled} onClick={onBack}>
            &larr; Back
          </button>
        </div>
      </div>
    </div>
  );
}
