/**
 * The game's sounds, and the preference that silences them.
 *
 * Nothing is loaded from disk: every sound is a handful of oscillators drawn on
 * the fly through the Web Audio API.
 *
 * The four that play while a game is running are all short — under a third of a
 * second — so a fast player never hears one land on top of the last:
 *
 *  - `tick`     — the last few seconds before an Endless round deals its tiles.
 *  - `deal`     — tiles arriving in your own pile, in any mode.
 *  - `attack`   — the same thing, but sent by the opponent in a Duel: lower and
 *                 falling, so incoming trouble never sounds like a gift.
 *  - `commit`   — a word going down on the board.
 *  - `overflow` — the loose pile has just gone over the limit. A warning, not a
 *                 verdict: the round's clock is now the deadline to dig under.
 *
 * The two that end a game may take their time, since nothing follows them:
 *
 *  - `lose`     — buried, or out of time. Four notes falling away.
 *  - `win`      — a multiplayer game taken. The same shape climbing.
 *
 * Browsers won't let audio start until the player has touched the page, so the
 * context is built on the first gesture (see `primeSound`) and every play nudges
 * it awake again — tabbing away suspends it.
 */

const STORAGE_KEY = 'nana.sound.v1';

export type SoundName =
  | 'tick'
  | 'deal'
  | 'attack'
  | 'commit'
  | 'overflow'
  | 'lose'
  | 'win';

/** One oscillator's worth of a sound. */
interface Blip {
  /** Hz to start at. */
  freq: number;
  /** Hz to slide to across the blip, when it slides at all. */
  to?: number;
  /** Seconds after the sound's start that this blip begins. */
  at: number;
  /** How long it rings, in seconds. */
  dur: number;
  /** Peak loudness, 0–1. Kept low: these play over a game, not as one. */
  gain: number;
  type?: OscillatorType;
}

const VOICES: Record<SoundName, readonly Blip[]> = {
  // Dry, high and quiet — five of these count a round down without nagging.
  tick: [{ freq: 1040, at: 0, dur: 0.035, gain: 0.05, type: 'square' }],
  // Tiles landing: three rising notes, light and quick.
  deal: [
    { freq: 523, at: 0, dur: 0.09, gain: 0.12, type: 'triangle' },
    { freq: 659, at: 0.055, dur: 0.09, gain: 0.12, type: 'triangle' },
    { freq: 784, at: 0.11, dur: 0.16, gain: 0.12, type: 'triangle' },
  ],
  // Tiles landing on you: the same idea inverted — low, falling, and reedy.
  attack: [
    { freq: 330, to: 145, at: 0, dur: 0.3, gain: 0.14, type: 'sawtooth' },
    { freq: 220, to: 98, at: 0.05, dur: 0.3, gain: 0.09, type: 'square' },
  ],
  // A word going down: two notes close enough together to read as one click.
  commit: [
    { freq: 660, at: 0, dur: 0.05, gain: 0.13, type: 'triangle' },
    { freq: 990, at: 0.035, dur: 0.1, gain: 0.1, type: 'triangle' },
  ],
  // Over the limit: a two-tone alarm, the second note lower than the first.
  // Nagging enough to look up at, and plainly not the sound of losing.
  overflow: [
    { freq: 466, at: 0, dur: 0.11, gain: 0.15, type: 'square' },
    { freq: 370, at: 0.13, dur: 0.16, gain: 0.15, type: 'square' },
  ],
  // Four notes falling away, the last one left ringing.
  lose: [
    { freq: 392, at: 0, dur: 0.16, gain: 0.14, type: 'triangle' },
    { freq: 311, at: 0.15, dur: 0.16, gain: 0.14, type: 'triangle' },
    { freq: 262, at: 0.3, dur: 0.16, gain: 0.14, type: 'triangle' },
    { freq: 196, at: 0.45, dur: 0.5, gain: 0.15, type: 'sawtooth' },
  ],
  // The same shape climbing, and up an octave by the end of it.
  win: [
    { freq: 523, at: 0, dur: 0.13, gain: 0.13, type: 'triangle' },
    { freq: 659, at: 0.1, dur: 0.13, gain: 0.13, type: 'triangle' },
    { freq: 784, at: 0.2, dur: 0.13, gain: 0.13, type: 'triangle' },
    { freq: 1047, at: 0.3, dur: 0.45, gain: 0.14, type: 'triangle' },
  ],
};

function loadPref(): boolean {
  try {
    // Sound is on until it's turned off, so a first-time player hears the game.
    return window.localStorage.getItem(STORAGE_KEY) !== 'off';
  } catch {
    // Storage blocked — play sound anyway; the toggle still works this session.
    return true;
  }
}

let enabled = loadPref();
let ctx: AudioContext | null = null;

/** The shared context, built on demand — and never while sound is off, so a
 * silenced game costs nothing. Null where Web Audio isn't available at all. */
function context(): AudioContext | null {
  if (!enabled) return null;
  if (ctx) return ctx;
  const Ctor =
    window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return null;
  try {
    ctx = new Ctor();
  } catch {
    ctx = null;
  }
  return ctx;
}

function wake(): AudioContext | null {
  const audio = context();
  if (audio && audio.state === 'suspended') void audio.resume();
  return audio;
}

export function soundEnabled(): boolean {
  return enabled;
}

export function setSoundEnabled(on: boolean): void {
  enabled = on;
  try {
    window.localStorage.setItem(STORAGE_KEY, on ? 'on' : 'off');
  } catch {
    // Storage full or blocked — the choice just won't survive a reload.
  }
  // Switching sound on happens inside a click, which is exactly the gesture a
  // browser wants before it will let audio play. Take it while we have it.
  if (on) wake();
}

/**
 * Watch for the first gesture of the visit and open the audio context on it.
 * Without this the first sound to play would be one nobody asked for by
 * touching anything — a countdown tick — and it would be swallowed.
 *
 * Returns the way to stop watching.
 */
export function primeSound(): () => void {
  const unlock = () => {
    wake();
    stop();
  };
  const stop = () => {
    window.removeEventListener('pointerdown', unlock);
    window.removeEventListener('keydown', unlock);
  };
  window.addEventListener('pointerdown', unlock);
  window.addEventListener('keydown', unlock);
  return stop;
}

/** Sound `name`, now. A no-op while sound is off or unavailable. */
export function playSound(name: SoundName): void {
  const audio = wake();
  if (!audio) return;
  // A hair in the future: scheduling at exactly `currentTime` can clip the
  // attack on a context that's still spinning up.
  const start = audio.currentTime + 0.01;
  for (const blip of VOICES[name]) {
    const osc = audio.createOscillator();
    const amp = audio.createGain();
    osc.type = blip.type ?? 'sine';
    const from = start + blip.at;
    const until = from + blip.dur;
    osc.frequency.setValueAtTime(blip.freq, from);
    if (blip.to !== undefined) osc.frequency.exponentialRampToValueAtTime(blip.to, until);
    // Ramped in and out rather than switched: a wave that starts at full
    // volume clicks, and one that stops there clicks again.
    amp.gain.setValueAtTime(0, from);
    amp.gain.linearRampToValueAtTime(blip.gain, from + 0.008);
    amp.gain.exponentialRampToValueAtTime(0.0001, until);
    osc.connect(amp).connect(audio.destination);
    osc.start(from);
    osc.stop(until + 0.02);
  }
}
