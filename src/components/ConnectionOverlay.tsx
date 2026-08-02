import type { BattleState } from '../game/battle';

interface ConnectionOverlayProps {
  /** True while this player's own link to the host is being redialed. */
  reconnecting: boolean;
  /** The shared state, for naming who else is having trouble. */
  state: BattleState | null;
  /** This player's id, so their own row isn't listed twice. */
  selfId: string | null;
  /** Give up and go home. */
  onLeave: () => void;
}

/**
 * The connection-trouble card. Two shapes of trouble land here:
 *
 *  - Our own link dropped: the session is quietly redialing the host with
 *    the same identity, and the game is held locally until it lands.
 *  - Someone else's link dropped: the host paused the game for everyone and
 *    is holding their seat; this says who everyone is waiting for.
 *
 * Either way the game isn't lost — that's the whole point of the overlay.
 */
export function ConnectionOverlay({ reconnecting, state, selfId, onLeave }: ConnectionOverlayProps) {
  const troubled =
    state?.players.filter(
      (p) => !p.connected && !p.left && !p.waiting && p.id !== selfId,
    ) ?? [];

  const paused = Boolean(state?.paused);
  if (!reconnecting && (!paused || troubled.length === 0)) return null;

  return (
    <div className="net-overlay" role="alertdialog" aria-modal="true" aria-label="Connection trouble">
      <div className="net-card">
        <span className="net-dot" aria-hidden="true" />
        <h2 className="net-title">
          {reconnecting ? 'Reconnecting…' : 'Game paused'}
        </h2>
        {reconnecting ? (
          <p className="net-note">
            Lost the connection to the host. Hold on — your seat is saved and
            we&rsquo;re dialing back in. Switching apps won&rsquo;t lose your game.
          </p>
        ) : (
          <>
            <p className="net-note">
              Waiting for {troubled.length === 1 ? 'a player' : 'players'} having connection
              trouble. The game resumes the moment they&rsquo;re back.
            </p>
            <ul className="net-players">
              {troubled.map((player) => (
                <li key={player.id} className="net-player">
                  <span className="net-dot" aria-hidden="true" />
                  {player.name}
                </li>
              ))}
            </ul>
          </>
        )}
        {reconnecting && (
          <div className="net-actions">
            <button type="button" className="btn" onClick={onLeave}>
              Leave the game
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
