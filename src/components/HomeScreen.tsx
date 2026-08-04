import { useState } from 'react';
import {
  BATTLE_INFO,
  DUEL_INFO,
  SOLO_BLITZ_INFO,
  SOLO_RELAXED_INFO,
  type ModeInfo,
  type SoloPace,
} from '../game/modes';
import {
  BlitzIcon,
  DuelIcon,
  HelpIcon,
  InfoIcon,
  PlayersIcon,
  SettingsIcon,
  SoloIcon,
  StatsIcon,
  TutorialIcon,
} from './icons';

interface HomeScreenProps {
  /** Start a solo Endless game at the chosen pace. */
  onPlaySolo: (pace: SoloPace) => void;
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
 * One mode: a full-width button carrying its icon and name, and a little ⓘ
 * beside it for the details. The button says only what the mode is called —
 * everything else is a tap away, so the choice reads at a glance.
 */
function ModeCard({
  info,
  icon,
  onClick,
  onInfo,
}: {
  info: ModeInfo;
  icon: React.ReactNode;
  onClick: () => void;
  onInfo: () => void;
}) {
  return (
    <div className="mode-card-row">
      <button type="button" className="mode-card" onClick={onClick}>
        <span className="mode-card-icon">{icon}</span>
        <span className="mode-card-name">{info.name}</span>
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

/** The utility row's buttons: an icon and a label, matching the mode buttons. */
function HomeAction({
  icon,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button type="button" className="btn home-action" onClick={onClick}>
      <span className="home-action-icon">{icon}</span>
      {label}
    </button>
  );
}

/**
 * The splash screen the app opens on: the game's name up top, then one column
 * of buttons — the modes, then the things that aren't a game. Picking a mode
 * starts it, except the multiplayer ones, which head to their lobby first.
 *
 * The column stays a single column at every width: it keeps the buttons under
 * one another wherever the thumb already is, and a four-across row of huge
 * targets on a desktop looked like a toolbar rather than a choice.
 */
export function HomeScreen({
  onPlaySolo,
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
            info={SOLO_RELAXED_INFO}
            icon={<SoloIcon />}
            onClick={() => onPlaySolo('relaxed')}
            onInfo={() => setInfoOf(SOLO_RELAXED_INFO)}
          />
          <ModeCard
            info={SOLO_BLITZ_INFO}
            icon={<BlitzIcon />}
            onClick={() => onPlaySolo('blitz')}
            onInfo={() => setInfoOf(SOLO_BLITZ_INFO)}
          />
          <ModeCard
            info={BATTLE_INFO}
            icon={<PlayersIcon />}
            onClick={onBattle}
            onInfo={() => setInfoOf(BATTLE_INFO)}
          />
          <ModeCard
            info={DUEL_INFO}
            icon={<DuelIcon />}
            onClick={onDuel}
            onInfo={() => setInfoOf(DUEL_INFO)}
          />
        </div>

        <div className="home-actions">
          <HomeAction icon={<TutorialIcon />} label="Tutorial" onClick={onTutorial} />
          <HomeAction icon={<HelpIcon />} label="How to play" onClick={onShowHowTo} />
          <HomeAction icon={<StatsIcon />} label="Stats" onClick={onShowStats} />
          <HomeAction icon={<SettingsIcon />} label="Settings" onClick={onShowSettings} />
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
