import { useEffect } from 'react';
import { CheckIcon, CloseIcon, CompassIcon, RotateIcon, TrashIcon } from './icons';

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
function DemoButton({
  children,
  tone,
  inline,
}: {
  children: React.ReactNode;
  tone?: 'confirm';
  inline?: boolean;
}) {
  return (
    <span
      className={`icon-btn howto-btn${tone ? ` icon-btn-${tone}` : ''}${
        inline ? ' howto-btn-inline' : ''
      }`}
      aria-hidden="true"
    >
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
              <DemoTile letter="n" state="valid" />
              <span>
                <strong>Green</strong> — a real word, connected to the rest of the board.
              </span>
            </li>
            <li className="howto-row">
              <DemoTile letter="p" state="disconnected" />
              <span>
                <strong>Orange</strong> — a real word, not connected.
              </span>
            </li>
            <li className="howto-row">
              <DemoTile letter="x" state="invalid" />
              <span>
                <strong>Red</strong> — not a real word.
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
                Tap an empty square, then{' '}
                <DemoButton tone="confirm" inline>
                  <CheckIcon />
                </DemoButton>{' '}
                or press <kbd>Enter</kbd> to confirm.
              </span>
            </li>
          </ul>
        </section>

        <section className="summary-section">
          <h2 className="summary-section-title">Spell first, then point</h2>
          <ul className="howto-list">
            <li className="howto-row">
              <DemoWord letters={['w', 'o', 'r', 'd']} />
              <span>Type out your word, then choose a cell to place it.</span>
            </li>
            <li className="howto-row">
              <DemoWord letters={['w', null, 'r', 'd']} />
              <span>
                Or use the gap tile (<kbd>Space</kbd>) in place of a letter that would overlap
                with another word.
                <br />
                Then tap the letter on the board where the overlapped letter would end up.
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
              <span>Rotate the selected word.</span>
            </li>
            <li className="howto-row">
              <DemoButton>
                <CompassIcon />
              </DemoButton>
              <span>Drag to move the selected word.</span>
            </li>
            <li className="howto-row">
              <DemoButton>
                <TrashIcon />
              </DemoButton>
              <span>Remove this word, sending its tiles back to the pile.</span>
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
