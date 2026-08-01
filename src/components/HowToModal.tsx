import { useEffect } from 'react';
import { CheckIcon, CloseIcon, CompassIcon, GapIcon, RotateIcon, TrashIcon } from './icons';

interface HowToModalProps {
  onClose: () => void;
}

/** A little non-interactive stand-in for a game tile, in any of its states. */
function DemoTile({
  letter,
  state,
}: {
  letter?: string;
  state?: 'valid' | 'invalid' | 'disconnected' | 'gap' | 'cursor';
}) {
  return (
    <span className={`howto-tile${state ? ` howto-tile-${state}` : ''}`} aria-hidden="true">
      {letter}
    </span>
  );
}

function DemoWord({
  letters,
  state,
}: {
  letters: Array<string | null>;
  state?: 'valid' | 'invalid' | 'disconnected';
}) {
  return (
    <span className="howto-tiles" aria-hidden="true">
      {letters.map((letter, i) => (
        // eslint-disable-next-line react/no-array-index-key
        <DemoTile key={i} letter={letter ?? undefined} state={letter === null ? 'gap' : state} />
      ))}
    </span>
  );
}

/** A game button shown for what it looks like, not for pressing. */
function DemoButton({ children, tone }: { children: React.ReactNode; tone?: 'confirm' }) {
  return (
    <span className={`icon-btn howto-btn${tone ? ` icon-btn-${tone}` : ''}`} aria-hidden="true">
      {children}
    </span>
  );
}

/**
 * The first-run tutorial: every way of getting a word onto the board, drawn
 * with the game's own tiles and buttons. Shown automatically the first time a
 * game is entered (see the localStorage flag in App), and any time after from
 * the menu. The X stays fixed at the top right however far the page scrolls.
 */
export function HowToModal({ onClose }: HowToModalProps) {
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  return (
    <div className="howto" role="dialog" aria-modal="true" aria-label="How to play">
      <button
        type="button"
        className="icon-btn howto-close"
        onClick={onClose}
        title="Close"
        aria-label="Close"
      >
        <CloseIcon />
      </button>

      <div className="howto-inner">
        <header className="summary-header">
          <h1 className="summary-title">How to play</h1>
          <p className="howto-goal">
            Weave <strong>every tile</strong> from your pile into <strong>one connected
            crossword</strong> of real words. Longer words score more.
          </p>
        </header>

        <section className="summary-section">
          <h2 className="summary-section-title">What the colours mean</h2>
          <ul className="howto-list">
            <li className="howto-row">
              <DemoWord letters={['n', 'a', 'n', 'a']} state="valid" />
              <span>
                <strong>Green</strong> — a real word, connected to the rest of your board. This is
                what you want everywhere.
              </span>
            </li>
            <li className="howto-row">
              <DemoWord letters={['p', 'e', 'e', 'l']} state="disconnected" />
              <span>
                <strong>Orange</strong> — a real word, but it&rsquo;s not connected to the rest of
                your crossword yet. Everything has to join into one group.
              </span>
            </li>
            <li className="howto-row">
              <DemoWord letters={['x', 'q', 'z']} state="invalid" />
              <span>
                <strong>Red</strong> — not a word. Fix it before it costs you the board.
              </span>
            </li>
          </ul>
        </section>

        <section className="summary-section">
          <h2 className="summary-section-title">Type straight onto the board</h2>
          <ul className="howto-list">
            <li className="howto-row">
              <DemoTile state="cursor" />
              <span>
                Tap any empty square and just start typing — your letters preview right on the
                board as you go.
              </span>
            </li>
            <li className="howto-row">
              <DemoButton tone="confirm">
                <CheckIcon />
              </DemoButton>
              <span>
                Press <kbd>Enter</kbd> or the confirm button to place the word.
              </span>
            </li>
          </ul>
        </section>

        <section className="summary-section">
          <h2 className="summary-section-title">Or spell first, then point</h2>
          <ul className="howto-list">
            <li className="howto-row">
              <DemoWord letters={['b', 'o', 'a', 'r', 'd']} />
              <span>
                Type letters (or tap tiles in your pile) before choosing a square — they wait in
                the bar at the bottom.
              </span>
            </li>
            <li className="howto-row">
              <DemoTile state="cursor" />
              <span>Then tap the empty square where the word should start, and confirm.</span>
            </li>
          </ul>
        </section>

        <section className="summary-section">
          <h2 className="summary-section-title">Overlap words easier with a gap letter</h2>
          <ul className="howto-list">
            <li className="howto-row">
              <DemoButton>
                <GapIcon />
              </DemoButton>
              <span>
                The gap tile (or <kbd>Space</kbd>) leaves a hole in your word for a letter
                that&rsquo;s already on the board.
              </span>
            </li>
            <li className="howto-row">
              <DemoWord letters={['b', null, 'a', 'r', 'd']} />
              <span>
                Spell around the hole — here <strong>B&nbsp;_&nbsp;A&nbsp;R&nbsp;D</strong> — then
                tap an <strong>O</strong> on the board. The word lands with that letter filling
                the gap, spelling BOARD.
              </span>
            </li>
          </ul>
        </section>

        <section className="summary-section">
          <h2 className="summary-section-title">Turn and move words</h2>
          <ul className="howto-list">
            <li className="howto-row">
              <DemoButton>
                <RotateIcon to="down" />
              </DemoButton>
              <span>
                Words read <strong>across</strong> or <strong>down</strong>. The turn button (or
                the arrow keys, or the little arrow on the square you picked) flips the direction
                before you place.
              </span>
            </li>
            <li className="howto-row">
              <DemoButton>
                <CompassIcon />
              </DemoButton>
              <span>
                Tap a placed tile to select its word — a control pops up. Drag the compass handle
                to move the whole word somewhere else, or turn it in place.
              </span>
            </li>
            <li className="howto-row">
              <DemoButton>
                <TrashIcon />
              </DemoButton>
              <span>
                The word&rsquo;s trash button sends all its letters back to your pile. Single
                tiles can also be dragged anywhere — or double-tapped to send them back.
              </span>
            </li>
          </ul>
        </section>

        <div className="summary-actions">
          <button type="button" className="btn btn-primary" onClick={onClose}>
            Got it — let&rsquo;s play
          </button>
        </div>
      </div>
    </div>
  );
}
