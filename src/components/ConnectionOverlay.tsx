interface ConnectionOverlayProps {
  /** True while this player's own link to the host is being redialed. */
  reconnecting: boolean;
  /** Give up and go home. */
  onLeave: () => void;
}

/**
 * The connection-trouble card, shown only for this player's own link. The
 * session is quietly redialing the host with the same identity; the battle
 * plays on for everyone else meanwhile. A quick return lands back on the
 * same board — a slow one rejoins as a spectator, dealt into the next game.
 * Other players' drops never raise this: the game simply continues, and the
 * host counts them out if they don't make it back.
 */
export function ConnectionOverlay({ reconnecting, onLeave }: ConnectionOverlayProps) {
  if (!reconnecting) return null;

  return (
    <div className="net-overlay" role="alertdialog" aria-modal="true" aria-label="Connection trouble">
      <div className="net-card">
        <span className="net-dot" aria-hidden="true" />
        <h2 className="net-title">Reconnecting…</h2>
        <p className="net-note">
          Lost the connection to the host — dialing back in now. Get back
          quickly and you&rsquo;ll pick up right where you left off; the battle
          plays on in the meantime.
        </p>
        <div className="net-actions">
          <button type="button" className="btn" onClick={onLeave}>
            Leave the game
          </button>
        </div>
      </div>
    </div>
  );
}
