import { useState } from 'react';
import { BATTLE_INFO, DUEL_INFO, ENDLESS_INFO, type ModeInfo } from '../game/modes';
import { InfoIcon } from './icons';

interface HomeScreenProps {
  /** Start a solo Endless game. */
  onPlayEndless: () => void;
  /** Head for the Survival door: host or join a multiplayer lobby. */
  onBattle: () => void;
  /** Head for the Duel door: the two-player lobby flow. */
  onDuel: () => void;
  /** Start the guided tutorial. */
  onTutorial: () => void;
  onShowHowTo: () => void;
  onShowStats: () => void;
  onShowSettings: () => void;
}

/**
 * One mode: a big button that starts it — just the name and its one-line
 * pitch — and a little ⓘ beside it for the full details, so the launch
 * buttons stay clean without hiding how each mode works.
 */
function ModeCard({
  info,
  onClick,
  onInfo,
}: {
  info: ModeInfo;
  onClick: () => void;
  onInfo: () => void;
}) {
  return (
    <div className="mode-card-row">
      <button type="button" className="mode-card" onClick={onClick}>
        <span className="mode-card-name">{info.name}</span>
        <span className="mode-card-tagline">{info.tagline}</span>
      </button>
      <button
        type="button"
        className="mode-info-btn"
        title={`About ${info.name}`}
        aria-label={`About ${info.name}`}
        onClick={onInfo}
      >
        <InfoIcon />
      </button>
    </div>
  );
}

/**
 * The splash screen the app opens on: the game's name up top and a button per
 * mode underneath. Picking one starts a fresh game in that mode — except the
 * multiplayer modes, which head to their lobby screens first. The tutorial
 * lives with the utility buttons at the bottom.
 */
export function HomeScreen({
  onPlayEndless,
  onBattle,
  onDuel,
  onTutorial,
  onShowHowTo,
  onShowStats,
  onShowSettings,
}: HomeScreenProps) {
  /** The mode whose details are up, or null while the sheet is closed. */
  const [infoOf, setInfoOf] = useState<ModeInfo | null>(null);

  return (
    <div className="home">
      <div className="home-inner">
        <header className="home-header">
          <h1 className="home-title">Word</h1>
          <p className="home-tagline">Race to weave every tile into one crossword.</p>
        </header>

        <div className="home-modes">
          <ModeCard
            info={ENDLESS_INFO}
            onClick={onPlayEndless}
            onInfo={() => setInfoOf(ENDLESS_INFO)}
          />
          <ModeCard info={BATTLE_INFO} onClick={onBattle} onInfo={() => setInfoOf(BATTLE_INFO)} />
          <ModeCard info={DUEL_INFO} onClick={onDuel} onInfo={() => setInfoOf(DUEL_INFO)} />
        </div>

        <div className="home-actions">
          <button type="button" className="btn" onClick={onTutorial}>
            Tutorial
          </button>
          <button type="button" className="btn" onClick={onShowHowTo}>
            How to play
          </button>
          <button type="button" className="btn" onClick={onShowStats}>
            Stats
          </button>
          <button type="button" className="btn" onClick={onShowSettings}>
            Settings
          </button>
        </div>
      </div>

      {infoOf && (
        <div className="splash-backdrop" onClick={() => setInfoOf(null)} role="presentation">
          <div
            className="dialog mode-info"
            role="dialog"
            aria-modal="true"
            aria-label={`About ${infoOf.name}`}
            onClick={(e) => e.stopPropagation()}
          >
            <span className="mode-card-name">{infoOf.name}</span>
            <span className="mode-card-tagline">{infoOf.tagline}</span>
            <span className="mode-card-details">
              {infoOf.details.map((detail) => (
                <span key={detail} className="mode-card-detail">
                  {detail}
                </span>
              ))}
            </span>
            <div className="dialog-actions">
              <button type="button" className="btn btn-primary" onClick={() => setInfoOf(null)}>
                Got it
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
