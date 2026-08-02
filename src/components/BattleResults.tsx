import { useMemo } from 'react';
import { ordinal, rankPlayers, type BattleState } from '../game/battle';

interface BattleResultsProps {
  state: BattleState;
  selfId: string;
  isHost: boolean;
  /** Host only: deal everyone into a fresh game right away. */
  onPlayAgain: () => void;
  /** Host only: gather everyone back in the lobby instead. */
  onToLobby: () => void;
  onLeave: () => void;
  /** Put the results away and look at the finished board. */
  onClose: () => void;
}

const MEDALS = ['🥇', '🥈', '🥉'];

/**
 * The end of a battle: who won, and the full standings. The host decides
 * what happens next — another game or back to the lobby — while everyone
 * else sees the same table and waits, or bows out.
 */
export function BattleResults({
  state,
  selfId,
  isHost,
  onPlayAgain,
  onToLobby,
  onLeave,
  onClose,
}: BattleResultsProps) {
  const ranked = useMemo(
    () => rankPlayers(state.players.filter((p) => !p.waiting)),
    [state.players],
  );
  const waiting = state.players.filter((p) => p.waiting);

  const winners = ranked.filter((entry) => entry.rank === 1);
  const selfWon = winners.some((entry) => entry.player.id === selfId);
  const title =
    winners.length > 1
      ? '🤝 It’s a tie!'
      : selfWon
        ? '🏆 You win!'
        : `🏆 ${winners[0]?.player.name ?? 'Nobody'} wins!`;

  return (
    <div className="summary" role="dialog" aria-modal="true" aria-label="Battle finished">
      <div className="summary-inner">
        <header className="summary-header">
          <span className="splash-eyebrow">Battle finished</span>
          <h1 className="summary-title">{title}</h1>
        </header>

        <section className="summary-section">
          <h2 className="summary-section-title">Standings</h2>
          <ol className="battle-results-list">
            {ranked.map(({ player, rank }) => (
              <li
                key={player.id}
                className={
                  'battle-results-row' +
                  (player.id === selfId ? ' battle-results-self' : '') +
                  (rank === 1 ? ' battle-results-winner' : '')
                }
              >
                <span className="battle-results-rank">{MEDALS[rank - 1] ?? ordinal(rank)}</span>
                <span className="battle-results-name">
                  {player.name}
                  {player.id === selfId && <span className="battle-chip battle-chip-you">You</span>}
                  {!player.connected && <span className="battle-results-left">left the game</span>}
                </span>
                <span className="battle-results-score">{player.score}</span>
              </li>
            ))}
          </ol>
          {waiting.length > 0 && (
            <p className="battle-results-waiting">
              Dealing in next game: {waiting.map((p) => p.name).join(', ')}
            </p>
          )}
        </section>

        <div className="summary-actions">
          {isHost ? (
            <>
              <button type="button" className="btn btn-primary" onClick={onPlayAgain}>
                Start another game
              </button>
              <button type="button" className="btn" onClick={onToLobby}>
                Back to the lobby
              </button>
            </>
          ) : (
            <p className="battle-status" role="status">
              Waiting for the host to start another game or reopen the lobby&hellip;
            </p>
          )}
          <button type="button" className="btn" onClick={onClose}>
            See the board
          </button>
          <button type="button" className="btn" onClick={onLeave}>
            Leave battle
          </button>
        </div>
      </div>
    </div>
  );
}
