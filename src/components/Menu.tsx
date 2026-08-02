import { useEffect, useRef, useState } from 'react';
import { MenuIcon } from './icons';

/** The battle-only entries: host controls, and leaving reads differently. */
export interface MenuBattleControls {
  isHost: boolean;
  /** Host: reset everyone and deal a fresh shared game. */
  onRestart: () => void;
  /** Host: end the game and gather every player in the lobby. */
  onToLobby: () => void;
}

interface MenuProps {
  /** Start the current mode over from scratch. Null hides the item — in a
   * battle only the host restarts, through the battle controls instead. */
  onResetGame: (() => void) | null;
  onShowHowTo: () => void;
  onShowStats: () => void;
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
  onResetGame,
  onShowHowTo,
  onShowStats,
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

  const item = (label: string, action: () => void) => (
    <button
      type="button"
      className="menu-item"
      role="menuitem"
      onClick={() => {
        setOpen(false);
        action();
      }}
    >
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
          {onResetGame && item('Reset game', onResetGame)}
          {battle?.isHost && item('Restart battle', battle.onRestart)}
          {battle?.isHost && item('Everyone to the lobby', battle.onToLobby)}
          {onShowSummary && item(battle ? 'Standings' : 'Final score', onShowSummary)}
          {item('How to play', onShowHowTo)}
          {item('Stats', onShowStats)}
          {item('Settings', onShowSettings)}
          {item(battle ? 'Leave game' : 'Return home', onReturnHome)}
        </div>
      )}
    </div>
  );
}
