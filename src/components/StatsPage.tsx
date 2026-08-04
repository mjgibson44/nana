import type { Stats } from '../game/stats';
import { CloseIcon } from './icons';

interface StatsPageProps {
  /** Null while the page is closed — nothing renders. */
  stats: Stats | null;
  onClose: () => void;
}

const timestamp = new Intl.DateTimeFormat(undefined, {
  dateStyle: 'medium',
  timeStyle: 'short',
});

/**
 * The stats page, reached from the home screen: how many games have been
 * finished, and the recent ones with their scores and when they were played.
 */
export function StatsPage({ stats, onClose }: StatsPageProps) {
  if (!stats) return null;

  const best = stats.recent.reduce((top, game) => Math.max(top, game.score), 0);

  return (
    <div className="summary" role="dialog" aria-modal="true" aria-label="Stats">
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
          <span className="splash-eyebrow">Your record</span>
          <h1 className="summary-title">Stats</h1>
        </header>

        <div className="summary-totals">
          <div className="summary-stat">
            <span className="summary-stat-value">{stats.gamesPlayed}</span>
            <span className="summary-stat-label">
              {stats.gamesPlayed === 1 ? 'Game played' : 'Games played'}
            </span>
          </div>
          {stats.recent.length > 0 && (
            <div className="summary-stat">
              <span className="summary-stat-value">{best}</span>
              <span className="summary-stat-label">Best recent score</span>
            </div>
          )}
        </div>

        <section className="summary-section">
          <h2 className="summary-section-title">Recent games</h2>
          {stats.recent.length === 0 ? (
            <p className="summary-empty">
              Nothing here yet — finish a game and it lands on this page.
            </p>
          ) : (
            <ul className="summary-words stats-games">
              {stats.recent.map((game) => (
                <li key={game.at} className="summary-word stats-game">
                  <span className="stats-game-when">{timestamp.format(game.at)}</span>
                  <span className="stats-game-words">
                    {game.words} {game.words === 1 ? 'word' : 'words'}
                  </span>
                  <span className="summary-word-points">{game.score}</span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <div className="summary-actions">
          <button type="button" className="btn btn-primary" onClick={onClose}>
            Back to the game
          </button>
        </div>
      </div>
    </div>
  );
}
