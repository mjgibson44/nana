/**
 * Inline SVG icons.
 *
 * Drawn rather than set in text because the ones that matter here — a four-way
 * compass, a turned arrow — have no glyph that renders dependably across
 * platforms, and these need to stay sharp at button size.
 *
 * Every icon inherits `currentColor` and sizes itself to the font, so buttons
 * control their own scale.
 */

interface IconProps {
  /** Overrides the default 1em box, in px. */
  size?: number;
}

function Svg({ size, children }: IconProps & { children: React.ReactNode }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size ?? '1em'}
      height={size ?? '1em'}
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

/** Four-way arrows: the universal "pick this up and move it" handle. */
export function CompassIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M12 3v18M3 12h18" />
      <path d="M12 3 9.5 5.5M12 3l2.5 2.5" />
      <path d="M12 21l-2.5-2.5M12 21l2.5-2.5" />
      <path d="M3 12l2.5-2.5M3 12l2.5 2.5" />
      <path d="M21 12l-2.5-2.5M21 12l-2.5 2.5" />
    </Svg>
  );
}

/**
 * An arrow bent through a right angle — the word turns, it doesn't just move.
 *
 * `to` is the direction the word will end up reading, and the arrow is drawn to
 * match: it sets off the way the word lies now and comes out pointing the way
 * it's going, so the button shows the turn rather than just naming it.
 */
export function RotateIcon({ to, ...props }: IconProps & { to: 'across' | 'down' }) {
  return (
    <Svg {...props}>
      {to === 'down' ? (
        <>
          {/* Runs across, then bends downward. */}
          <path d="M5 5h7a5 5 0 0 1 5 5v9" />
          <path d="M13 15l4 4 4-4" />
        </>
      ) : (
        <>
          {/* Runs down, then bends out to the right. */}
          <path d="M5 5v7a5 5 0 0 0 5 5h9" />
          <path d="M15 13l4 4-4 4" />
        </>
      )}
    </Svg>
  );
}

export function UndoIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M4 8h11a5 5 0 0 1 0 10H7" />
      <path d="M8 4 4 8l4 4" />
    </Svg>
  );
}

/** The keyboard backspace key: a left-pointing key cap with an × inside. */
export function BackspaceIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M9 5h10a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-6-7 6-7z" />
      <path d="M11.5 9.5l5 5M16.5 9.5l-5 5" />
    </Svg>
  );
}

export function ShuffleIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M3 7h4l10 10h4" />
      <path d="M18 4l3 3-3 3" />
      <path d="M3 17h4l3-3" />
      <path d="M14 10l3-3h4" />
      <path d="M18 20l3-3-3-3" />
    </Svg>
  );
}

/** A dashed square: a hole in the word, waiting on a letter already placed. */
export function GapIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <rect x="4" y="4" width="16" height="16" rx="3" strokeDasharray="4 3" />
    </Svg>
  );
}

export function MenuIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M4 7h16M4 12h16M4 17h16" />
    </Svg>
  );
}

export function CheckIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M5 13l4.5 4.5L19 6.5" />
    </Svg>
  );
}

export function CloseIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M6 6l12 12M18 6L6 18" />
    </Svg>
  );
}

/** A trash can: the word comes off the board and its letters go back to the
 * pile. */
export function TrashIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M4 7h16" />
      <path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
      <path d="M6 7l1 12a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-12" />
      <path d="M10 11v6M14 11v6" />
    </Svg>
  );
}
