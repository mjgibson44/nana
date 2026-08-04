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

/** An i in a ring: there's more to read about this. */
export function InfoIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11.5V16" />
      <path d="M12 8h.01" />
    </Svg>
  );
}

/* ---------- home screen ---------- */

/** One player: Solo. */
export function SoloIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="8" r="3.5" />
      <path d="M5.5 20a6.5 6.5 0 0 1 13 0" />
    </Svg>
  );
}

/** A lightning bolt: Blitz, the pile racing you on a clock. */
export function BlitzIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M13.5 3L6 13.5h5L9.5 21 18 10.5h-5L13.5 3z" />
    </Svg>
  );
}

/** A small bounded grid: Puzzle, a board with real edges to fill. */
export function PuzzleIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <rect x="4" y="4" width="16" height="16" rx="2" />
      <path d="M9.33 4v16M14.67 4v16M4 9.33h16M4 14.67h16" />
    </Svg>
  );
}

/** A crowd: Survival, the whole field racing at once. */
export function PlayersIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="9" cy="8.5" r="3" />
      <path d="M3 19a6 6 0 0 1 12 0" />
      <path d="M16 6.2a3 3 0 0 1 0 4.6" />
      <path d="M18.5 19a6 6 0 0 0-2.6-4.4" />
    </Svg>
  );
}

/**
 * Crossed swords: a Duel, two players head to head. Two blades on the
 * diagonals, each with a crossguard set square across it above the hilt.
 */
export function DuelIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M18.5 5.5L5 19" />
      <path d="M6.5 13L11 17.5" />
      <path d="M5.5 5.5L19 19" />
      <path d="M13 17.5L17.5 13" />
    </Svg>
  );
}

/** A graduation cap: the guided walkthrough. */
export function TutorialIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M12 4L2 9l10 5 10-5-10-5z" />
      <path d="M6 11.5V17c0 1.4 2.7 2.6 6 2.6s6-1.2 6-2.6v-5.5" />
    </Svg>
  );
}

/** A question mark in a ring: how the game is played. */
export function HelpIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="M9.3 9.2a2.8 2.8 0 0 1 5.5.8c0 1.9-2.8 2.2-2.8 4" />
      <path d="M12 17.6h.01" />
    </Svg>
  );
}

/** Bars on a baseline: the stats page. */
export function StatsIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M4 20h16" />
      <path d="M7.5 20v-5M12 20V6.5M16.5 20v-8.5" />
    </Svg>
  );
}

/**
 * Two sliders with their knobs: the settings page. A cog's teeth turn to mush
 * at this size — sliders stay legible, and this screen is preferences anyway.
 */
export function SettingsIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M3.5 8.5h6.2M15.3 8.5h5.2" />
      <circle cx="12.5" cy="8.5" r="2.4" />
      <path d="M3.5 15.5h3.2M12.3 15.5h8.2" />
      <circle cx="9.5" cy="15.5" r="2.4" />
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
