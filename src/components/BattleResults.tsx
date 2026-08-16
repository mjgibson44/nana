import { useMemo } from 'react';
import {
  battleWinners,
  ordinal,
  rankByElimination,
  type BattlePlayer,
  type BattleState,
} from '../game/battle';
import { WordReport, type ScoredWord } from './GameSummary';

interface BattleResultsProps {
  state: BattleState;
  selfId: string;
  isHost: boolean;
  /** This player's own finished board — the same word report the solo summary
   * shows. Null for a player who never played this game (joined mid-game). */
  words: ScoredWord[] | null;
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
 * The end of a battle: who won, the full standings — the whole field ranked
 * by how long each player lasted, the winner first, then everyone else in
 * reverse order of falling — and, below them, this player's own words, the
 * same report the solo summary gives. The ways onward sit right under the
 * headline: the host decides what happens next — another game or back to the
 * lobby — while everyone else sees the same table and waits, or bows out.
 */
export function BattleResults({
  state,
  selfId,
  isHost,
  words,
  onPlayAgain,
  onToLobby,
  onLeave,
  onClose,
}: BattleResultsProps) {
  const contestants = useMemo(
    () => state.players.filter((p) => !p.waiting),
    [state.players],
  );

  // The standings are the elimination order, read backwards: the last one
  // standing leads, the first buried brings up the rear.
  const rows = useMemo(() => rankByElimination(contestants), [contestants]);

  const waiting = state.players.filter((p) => p.waiting);

  const winners = useMemo(() => battleWinners(state), [state]);
  const selfWon = winners.some((player) => player.id === selfId);
  const title =
    state.winnerId === null
      ? 'It’s a draw!'
      : selfWon
        ? 'You win the battle!'
        : `${winners[0]?.name ?? 'Nobody'} wins the battle!`;

  const outcome = (player: BattlePlayer) =>
    player.id === state.winnerId ? 'survived' : player.left ? 'left' : 'buried';

  // A battle can only go again with enough seats still filled.
  const present = state.players.filter((p) => p.connected && !p.left).length;
  const canRestart = present >= 2;

  return (
    <div className="summary" role="dialog" aria-modal="true" aria-label="Game finished">
      <div className="summary-inner">
        <header className="summary-header">
          <span className="splash-eyebrow">Battle finished</span>
          <h1 className="summary-title">{title}</h1>
        </header>

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
                <span className="battle-results-score">{outcome(player)}</span>
              </li>
            ))}
          </ol>
          {waiting.length > 0 && (
            <p className="battle-results-waiting">
              Dealing in next game: {waiting.map((p) => p.name).join(', ')}
            </p>
          )}
        </section>

        {words && <WordReport words={words} />}
      </div>
    </div>
  );
}
