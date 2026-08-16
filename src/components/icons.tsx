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

/** A crown: Battle, the free-for-all the last player standing takes. */
export function CrownIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M4.5 18.5L3 7.5l5 4L12 5l4 6.5 5-4-1.5 11h-15z" />
      <path d="M8.5 15h7" />
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

/** A gear: the settings page. */
export function SettingsIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </Svg>
  );
}

/** An arrow chasing its own tail: start this game over from scratch. */
export function RestartIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M21 4v6h-6" />
      <path d="M20.5 14a8.5 8.5 0 1 1-2-8.5L21 8" />
    </Svg>
  );
}

/** Two people: the whole room, gathered back in the lobby. */
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

/** A doorway with an arrow through it: leave for home (or the lobby). */
export function ExitIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
      <path d="M16 17l5-5-5-5" />
      <path d="M21 12H9" />
    </Svg>
  );
}

/** The two bars every player already reads as "held": the game is stopped
 * where it stands, not finished. */
export function PauseIcon(props: IconProps) {
  return (
    <Svg {...props}>
      <path d="M9 5v14M15 5v14" />
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
