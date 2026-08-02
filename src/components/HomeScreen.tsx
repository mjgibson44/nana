import { BATTLE_INFO, MODES, type GameMode } from '../game/modes';

interface HomeScreenProps {
  onPlay: (mode: GameMode) => void;
  /** Head for the Endless Battle door: host or join a multiplayer lobby. */
  onBattle: () => void;
  onShowHowTo: () => void;
  onShowStats: () => void;
}

/**
 * The splash screen the app opens on: the game's name up top and a card per
 * mode underneath. Picking a card starts a fresh game in that mode — except
 * Endless Battle, which heads to its lobby screens first.
 */
export function HomeScreen({ onPlay, onBattle, onShowHowTo, onShowStats }: HomeScreenProps) {
  return (
    <div className="home">
      <div className="home-inner">
        <header className="home-header">
          <h1 className="home-title">Word</h1>
          <p className="home-tagline">Race to weave every tile into one crossword.</p>
        </header>

        <div className="home-modes">
          {MODES.map((mode) => (
            <button
              key={mode.id}
              type="button"
              className="mode-card"
              onClick={() => onPlay(mode.id)}
            >
              <span className="mode-card-name">{mode.name}</span>
              <span className="mode-card-tagline">{mode.tagline}</span>
              <span className="mode-card-details">
                {mode.details.map((detail) => (
                  <span key={detail} className="mode-card-detail">
                    {detail}
                  </span>
                ))}
              </span>
              <span className="mode-card-play">Play &rarr;</span>
            </button>
          ))}
          <button type="button" className="mode-card" onClick={onBattle}>
            <span className="mode-card-name">{BATTLE_INFO.name}</span>
            <span className="mode-card-tagline">{BATTLE_INFO.tagline}</span>
            <span className="mode-card-details">
              {BATTLE_INFO.details.map((detail) => (
                <span key={detail} className="mode-card-detail">
                  {detail}
                </span>
              ))}
            </span>
            <span className="mode-card-play">Play &rarr;</span>
          </button>
        </div>

        <div className="home-actions">
          <button type="button" className="btn" onClick={onShowHowTo}>
            How to play
          </button>
          <button type="button" className="btn" onClick={onShowStats}>
            Stats
          </button>
        </div>
      </div>
    </div>
  );
}
