import { useMemo } from 'react';
import {
  battleWinners,
  ordinal,
  rankByElimination,
  rankPlayers,
  type BattlePlayer,
  type BattleState,
} from '../game/battle';

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
 * The end of a multiplayer game: who won, and the full standings. The host
 * decides what happens next — another game or back to the lobby — while
 * everyone else sees the same table and waits, or bows out.
 *
 * An Endless Battle ranks by score. A Duel is simpler: the survivor named by
 * the host wins, whatever the scores say. A Battle ranks the whole field by
 * how long each player lasted — the winner first, then everyone else in
 * reverse order of falling.
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
  const duel = state.mode === 'duel';
  const battle = state.mode === 'battle';
  const contestants = useMemo(
    () => state.players.filter((p) => !p.waiting),
    [state.players],
  );

  const rows = useMemo(() => {
    if (battle) {
      // A battle's standings are the elimination order, read backwards:
      // the last one standing leads, the first buried brings up the rear.
      return rankByElimination(contestants).map(({ player, rank }) => ({ player, rank }));
    }
    if (!duel) {
      return rankPlayers(contestants).map(({ player, rank }) => ({ player, rank }));
    }
    // A duel's order is survival, not score: the winner first.
    const sorted = [...contestants].sort((a, b) => {
      const aWon = a.id === state.winnerId ? 0 : 1;
      const bWon = b.id === state.winnerId ? 0 : 1;
      return aWon - bWon;
    });
    return sorted.map((player, i) => ({
      player,
      rank: state.winnerId === null ? 1 : i + 1,
    }));
  }, [duel, battle, contestants, state.winnerId]);

  const waiting = state.players.filter((p) => p.waiting);

  const winners = useMemo(() => battleWinners(state), [state]);
  const selfWon = winners.some((player) => player.id === selfId);
  const title =
    duel || battle
      ? state.winnerId === null
        ? 'It’s a draw!'
        : selfWon
          ? `You win the ${duel ? 'duel' : 'battle'}!`
          : `${winners[0]?.name ?? 'Nobody'} wins the ${duel ? 'duel' : 'battle'}!`
      : winners.length > 1
        ? 'It’s a tie!'
        : selfWon
          ? 'You win!'
          : `${winners[0]?.name ?? 'Nobody'} wins!`;

  const survivalOutcome = (player: BattlePlayer) =>
    player.id === state.winnerId ? 'survived' : player.left ? 'left' : 'buried';

  // A duel or battle can only go again with enough seats still filled.
  const present = state.players.filter((p) => p.connected && !p.left).length;
  const canRestart = (!duel && !battle) || present >= 2;

  return (
    <div className="summary" role="dialog" aria-modal="true" aria-label="Game finished">
      <div className="summary-inner">
        <header className="summary-header">
          <span className="splash-eyebrow">
            {duel ? 'Duel finished' : battle ? 'Battle finished' : 'Survival finished'}
          </span>
          <h1 className="summary-title">{title}</h1>
        </header>

        <section className="summary-section">
          <h2 className="summary-section-title">Standings</h2>
          <ol className="battle-results-list">
            {rows.map(({ player, rank }) => (
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
                  {player.left && <span className="battle-results-left">left the game</span>}
                </span>
                <span className="battle-results-score">
                  {duel || battle ? survivalOutcome(player) : player.score}
                </span>
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
              {canRestart && (
                <button type="button" className="btn btn-primary" onClick={onPlayAgain}>
                  Start another game
                </button>
              )}
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
            Leave game
          </button>
        </div>
      </div>
    </div>
  );
}
