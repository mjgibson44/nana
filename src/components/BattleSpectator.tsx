import { useMemo } from 'react';
import { ordinal, rankByElimination, type BattleState } from '../game/battle';
import { BATTLE_PILE_LIMIT } from '../game/modes';

interface BattleSpectatorProps {
  /** The host's latest broadcast — the card re-renders live off it. */
  state: BattleState;
  selfId: string;
  isHost: boolean;
  /** Host only: reset everyone and deal a fresh shared game. */
  onRestart: () => void;
  /** Host only: end the game and gather every player in the lobby. */
  onToLobby: () => void;
  onLeave: () => void;
}

/**
 * Where an eliminated Battle player watches from. Their game is over but the
 * battle isn't, so this covers the dead board — there's nothing left to do
 * on it — and follows the field live off the host's broadcasts instead:
 * who's still standing and how deep their piles are, who has fallen, in the
 * order the final standings will read. It can't be put away; the results
 * screen takes over the moment the battle is decided.
 *
 * It also covers the header, so the actions that still matter move onto the
 * card: anyone can leave, and a host keeps their controls — being knocked
 * out doesn't stop them refereeing.
 */
export function BattleSpectator({
  state,
  selfId,
  isHost,
  onRestart,
  onToLobby,
  onLeave,
}: BattleSpectatorProps) {
  const contestants = useMemo(
    () => state.players.filter((p) => !p.waiting),
    [state.players],
  );
  // Standing players lead in seat order, then the fallen, most recent first —
  // already the order the final standings will read in.
  const field = useMemo(
    () => rankByElimination(contestants).map(({ player }) => player),
    [contestants],
  );
  // Never counts this player: they're out — that's why they're here — even
  // in the beat before the host's echo of their fall lands.
  const standing = contestants.filter(
    (p) => p.id !== selfId && !p.buried && !p.left,
  ).length;

  /**
   * This player's final place, known the moment they fall: the fall order
   * fully decides a Battle's standings, so going out k-th of n means
   * finishing (n − k + 1)th whatever happens after. Null only until the
   * host's broadcast writes the fall down.
   *
   * A player whose connection outlasted the host's grace isn't among the
   * contestants at all any more — they rejoined as `waiting`, dealt into
   * the next game — so `self` is undefined and the note says what actually
   * happened instead of blaming their pile.
   */
  const self = contestants.find((p) => p.id === selfId);
  const dropped = self === undefined;
  const place =
    self !== undefined && self.outOrder !== null
      ? contestants.length - self.outOrder + 1
      : null;

  return (
    <div className="spectate" role="dialog" aria-modal="true" aria-label="Spectating">
      <div className="spectate-card">
        <span className="splash-eyebrow">Battle</span>
        <h2 className="spectate-title">You&rsquo;re out!</h2>
        <p className="spectate-note">
          {dropped ? (
            <>
              Your connection dropped and the battle went on without you
              &mdash; you&rsquo;re back in and deal into the next game.
            </>
          ) : (
            <>
              Your pile buried you
              {place !== null && (
                <> &mdash; you finish {ordinal(place)} of {contestants.length}</>
              )}
              .
            </>
          )}{' '}
          The battle rages on below; the standings come up when it&rsquo;s decided.
        </p>
        <p className="spectate-standing" role="status">
          {standing} player{standing === 1 ? '' : 's'} still standing
        </p>
        <ol className="spectate-players">
          {field.map((player) => {
            // This player is out however stale the broadcast in hand is.
            const fallen = player.buried || player.left || player.id === selfId;
            return (
              <li
                key={player.id}
                className={
                  'spectate-player' +
                  (player.id === selfId ? ' spectate-self' : '') +
                  (fallen ? ' spectate-fallen' : '')
                }
              >
                <span className="spectate-player-name">
                  {player.name}
                  {player.id === selfId && (
                    <span className="battle-chip battle-chip-you">You</span>
                  )}
                </span>
                <span className="spectate-player-state">
                  {fallen ? (
                    <>{player.left ? 'left' : 'out'} 💀</>
                  ) : (
                    `${player.tiles}/${BATTLE_PILE_LIMIT} tiles`
                  )}
                </span>
              </li>
            );
          })}
        </ol>
        <div className="spectate-actions">
          {isHost && (
            <>
              <button type="button" className="btn" onClick={onRestart}>
                Restart battle
              </button>
              <button type="button" className="btn" onClick={onToLobby}>
                Everyone to the lobby
              </button>
            </>
          )}
          <button type="button" className="btn" onClick={onLeave}>
            Leave game
          </button>
        </div>
      </div>
    </div>
  );
}
