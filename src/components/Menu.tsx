import { useEffect, useRef, useState } from 'react';
import { MenuIcon } from './icons';

interface MenuProps {
  /** Start the current mode over from scratch. */
  onResetGame: () => void;
  onShowHowTo: () => void;
  onShowStats: () => void;
  /** Reopen the final-score breakdown; null while the game is still going. */
  onShowSummary: (() => void) | null;
  /** Leave the game and go back to the mode-picking splash screen. */
  onReturnHome: () => void;
}

/** Header menu for the actions that aren't part of playing a turn. */
export function Menu({
  onResetGame,
  onShowHowTo,
  onShowStats,
  onShowSummary,
  onReturnHome,
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
          {item('Reset game', onResetGame)}
          {onShowSummary && item('Final score', onShowSummary)}
          {item('How to play', onShowHowTo)}
          {item('Stats', onShowStats)}
          {item('Return home', onReturnHome)}
        </div>
      )}
    </div>
  );
}
