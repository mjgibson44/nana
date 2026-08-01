import { useEffect, useRef, useState } from 'react';
import { MenuIcon } from './icons';

interface MenuProps {
  onNewGame: () => void;
  onShowStats: () => void;
  /** Reopen the final-score breakdown; null while the game is still going. */
  onShowSummary: (() => void) | null;
}

/** Header menu for the actions that aren't part of playing a turn. */
export function Menu({ onNewGame, onShowStats, onShowSummary }: MenuProps) {
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
          <button
            type="button"
            className="menu-item"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onNewGame();
            }}
          >
            New game
          </button>
          {onShowSummary && (
            <button
              type="button"
              className="menu-item"
              role="menuitem"
              onClick={() => {
                setOpen(false);
                onShowSummary();
              }}
            >
              Final score
            </button>
          )}
          <button
            type="button"
            className="menu-item"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onShowStats();
            }}
          >
            Stats
          </button>
        </div>
      )}
    </div>
  );
}
