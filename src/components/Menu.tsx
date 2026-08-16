import { useEffect, useRef, useState } from 'react';
import {
  ExitIcon,
  MenuIcon,
  PauseIcon,
  PlayersIcon,
  RestartIcon,
  SettingsIcon,
  StatsIcon,
} from './icons';

/** The battle-only entries: host controls, and leaving reads differently. */
export interface MenuBattleControls {
  isHost: boolean;
  /** The battle is decided. Ending a live game and regrouping after one are
   * different asks, so the lobby item changes hands and words on it. */
  finished: boolean;
  /** Host: reset everyone and deal a fresh shared game. */
  onRestart: () => void;
  /** Back to the lobby. From the host this gathers every player there —
   * mid-game that means ending the game; a guest gets it only once the game
   * is finished, to go wait in the room for the host's next move. */
  onToLobby: () => void;
}

interface MenuProps {
  /** Hold the game where it stands and cover the board. Null hides the item —
   * a finished game has nothing to hold, and a multiplayer game runs on one
   * clock nobody gets to stop for themselves. */
  onPause: (() => void) | null;
  /** Start the current mode over from scratch. Null hides the item — in a
   * battle only the host restarts, through the battle controls instead. */
  onResetGame: (() => void) | null;
  onShowSettings: () => void;
  /** Reopen the final-score breakdown; null while the game is still going. */
  onShowSummary: (() => void) | null;
  /** Leave the game and go back to the mode-picking splash screen. In a
   * battle this leaves the battle (and, for the host, closes it). */
  onReturnHome: () => void;
  /** Present only while playing a battle. */
  battle?: MenuBattleControls | null;
}

/** Header menu for the actions that aren't part of playing a turn. */
export function Menu({
  onPause,
  onResetGame,
  onShowSettings,
  onShowSummary,
  onReturnHome,
  battle = null,
}: MenuProps) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // Clicking anywhere else, or pressing Escape, closes it.
  useEffect(() => {
    if (!open) return;
    const onPointerDown = (e: PointerEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    window.addEventListener('pointerdown', onPointerDown);
    window.addEventListener('keydown', onKeyDown);
    return () => {
      window.removeEventListener('pointerdown', onPointerDown);
      window.removeEventListener('keydown', onKeyDown);
    };
  }, [open]);

  const item = (icon: React.ReactNode, label: string, action: () => void) => (
    <button
      type="button"
      className="menu-item"
      role="menuitem"
      onClick={() => {
        setOpen(false);
        action();
      }}
    >
      <span className="menu-item-icon" aria-hidden="true">
        {icon}
      </span>
      {label}
    </button>
  );

  return (
    <div className="menu" ref={ref}>
      <button
        type="button"
        className="icon-btn menu-btn"
        title="Menu"
        aria-label="Menu"
        aria-expanded={open}
        onClick={(e) => {
          e.currentTarget.blur();
          setOpen((was) => !was);
        }}
      >
        <MenuIcon />
      </button>

      {open && (
        <div className="menu-panel" role="menu">
          {/* First: it's the one item wanted mid-turn, with a clock running. */}
          {onPause && item(<PauseIcon />, 'Pause', onPause)}
          {onResetGame && item(<RestartIcon />, 'Reset game', onResetGame)}
          {battle?.isHost &&
            item(
              <RestartIcon />,
              battle.finished ? 'Start another game' : 'Restart battle',
              battle.onRestart,
            )}
          {battle &&
            (battle.isHost || battle.finished) &&
            item(
              <PlayersIcon />,
              battle.finished ? 'Back to the lobby' : 'Everyone to the lobby',
              battle.onToLobby,
            )}
          {onShowSummary &&
            item(<StatsIcon />, battle ? 'Standings' : 'Final score', onShowSummary)}
          {item(<SettingsIcon />, 'Settings', onShowSettings)}
          {item(<ExitIcon />, battle ? 'Leave game' : 'Return home', onReturnHome)}
        </div>
      )}
    </div>
  );
}
