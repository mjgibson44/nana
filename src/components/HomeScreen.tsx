import {
  BATTLE_INFO,
  DUEL_INFO,
  ENDLESS_INFO,
  TUTORIAL_INFO,
  type ModeInfo,
} from '../game/modes';

interface HomeScreenProps {
  /** Start a solo Endless game. */
  onPlayEndless: () => void;
  /** Head for the Endless Battle door: host or join a multiplayer lobby. */
  onBattle: () => void;
  /** Head for the Duel door: the two-player lobby flow. */
  onDuel: () => void;
  /** Start the guided tutorial. */
  onTutorial: () => void;
  onShowHowTo: () => void;
  onShowStats: () => void;
  onShowSettings: () => void;
}

function ModeCard({ info, onClick }: { info: ModeInfo; onClick: () => void }) {
  return (
    <button type="button" className="mode-card" onClick={onClick}>
      <span className="mode-card-name">{info.name}</span>
      <span className="mode-card-tagline">{info.tagline}</span>
      <span className="mode-card-details">
        {info.details.map((detail) => (
          <span key={detail} className="mode-card-detail">
            {detail}
          </span>
        ))}
      </span>
      <span className="mode-card-play">Play &rarr;</span>
    </button>
  );
}

/**
 * The splash screen the app opens on: the game's name up top and a card per
 * mode underneath. Picking a card starts a fresh game in that mode — except
 * the multiplayer modes, which head to their lobby screens first.
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
  return (
    <div className="home">
      <div className="home-inner">
        <header className="home-header">
          <h1 className="home-title">Word</h1>
          <p className="home-tagline">Race to weave every tile into one crossword.</p>
        </header>

        <div className="home-modes">
          <ModeCard info={ENDLESS_INFO} onClick={onPlayEndless} />
          <ModeCard info={BATTLE_INFO} onClick={onBattle} />
          <ModeCard info={DUEL_INFO} onClick={onDuel} />
          <ModeCard info={TUTORIAL_INFO} onClick={onTutorial} />
        </div>

        <div className="home-actions">
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
    </div>
  );
}
