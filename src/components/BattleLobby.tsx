import { useEffect, useState } from 'react';
import { battleLink, type BattleState } from '../game/battle';
import { BATTLE_MAX_PLAYERS, BATTLE_MIN_PLAYERS } from '../game/modes';

interface BattleLobbyProps {
  state: BattleState;
  code: string;
  selfId: string;
  isHost: boolean;
  onStart: () => void;
  onLeave: () => void;
}

/** Put text on the clipboard, however this browser lets us. */
async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Clipboard API blocked (http, permissions) — the old escape hatch.
    const scratch = document.createElement('textarea');
    scratch.value = text;
    scratch.style.position = 'fixed';
    scratch.style.opacity = '0';
    document.body.appendChild(scratch);
    scratch.select();
    let ok = false;
    try {
      ok = document.execCommand('copy');
    } catch {
      ok = false;
    }
    scratch.remove();
    return ok;
  }
}

function CopyButton({ label, text }: { label: string; text: string }) {
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), 1600);
    return () => window.clearTimeout(timer);
  }, [copied]);
  return (
    <button
      type="button"
      className="btn"
      onClick={async () => {
        if (await copyText(text)) setCopied(true);
      }}
    >
      {copied ? 'Copied!' : label}
    </button>
  );
}

/**
 * The room where a multiplayer game gathers. The host shares the code (or
 * the link that carries it) and starts the game once everyone's in; everyone
 * else watches the roster fill. A player who joins while a game is running
 * waits here for the next one. A Duel seats exactly two and a Battle two to
 * eight, so their start buttons wait for enough of a field.
 */
export function BattleLobby({ state, code, selfId, isHost, onStart, onLeave }: BattleLobbyProps) {
  const host = state.players.find((p) => p.host);
  const gameRunning = state.phase !== 'lobby';
  const alone = state.players.length === 1;
  const duel = state.mode === 'duel';
  const battle = state.mode === 'battle';
  const seated = state.players.filter((p) => !p.left).length;
  const duelReady = seated >= 2;
  const battleReady = seated >= BATTLE_MIN_PLAYERS;

  return (
    <div className="home">
      <div className="home-inner battle-inner">
        <header className="home-header">
          <span className="splash-eyebrow">
            {duel ? 'Duel' : battle ? 'Battle' : 'Survival'}
          </span>
          <h1 className="home-title battle-lobby-title">Lobby</h1>
        </header>

        <div className="battle-card">
          <div className="battle-code-block">
            <span className="battle-label">Game code</span>
            <span className="battle-code" aria-label={`Game code ${code.split('').join(' ')}`}>
              {code}
            </span>
            <div className="battle-share">
              <CopyButton label="Copy code" text={code} />
              <CopyButton label="Copy invite link" text={battleLink(code)} />
            </div>
          </div>

          <ul className="battle-roster">
            {state.players.map((player) => (
              <li key={player.id} className="battle-roster-row">
                <span className="battle-roster-name">
                  {player.name}
                  {player.host && <span className="battle-chip">Host</span>}
                  {player.id === selfId && <span className="battle-chip battle-chip-you">You</span>}
                </span>
                {!player.connected ? (
                  <span className="battle-roster-note">reconnecting…</span>
                ) : gameRunning ? (
                  <span className="battle-roster-note">
                    {player.waiting ? 'next game' : player.buried ? 'out' : 'playing'}
                  </span>
                ) : null}
              </li>
            ))}
          </ul>

          {gameRunning ? (
            <p className="battle-status" role="status">
              A game is running — you&rsquo;ll deal in when the next one starts.
            </p>
          ) : isHost ? (
            <>
              {duel && !duelReady && (
                <p className="battle-status">
                  A duel needs two — share the code and wait for your opponent.
                </p>
              )}
              {battle &&
                (battleReady ? (
                  <p className="battle-status">
                    {seated} of {BATTLE_MAX_PLAYERS} seats filled — start now, or wait for more.
                  </p>
                ) : (
                  <p className="battle-status">
                    A battle needs at least two — share the code and gather up to{' '}
                    {BATTLE_MAX_PLAYERS} players.
                  </p>
                ))}
              {!duel && !battle && alone && (
                <p className="battle-status">
                  Share the code so friends can join — or start solo to warm up.
                </p>
              )}
              <button
                type="button"
                className="btn btn-primary battle-wide-btn"
                disabled={(duel && !duelReady) || (battle && !battleReady)}
                onClick={onStart}
              >
                {state.game === 0
                  ? duel
                    ? 'Start the duel'
                    : battle
                      ? 'Start the battle'
                      : 'Start game'
                  : 'Start another game'}
              </button>
            </>
          ) : (
            <p className="battle-status" role="status">
              Waiting for {host?.name ?? 'the host'} to start the game&hellip;
            </p>
          )}
        </div>

        <div className="home-actions">
          <button type="button" className="btn" onClick={onLeave}>
            {isHost ? 'Close lobby' : 'Leave lobby'}
          </button>
        </div>
      </div>
    </div>
  );
}
