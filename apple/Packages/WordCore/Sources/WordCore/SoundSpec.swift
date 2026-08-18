/// The game's synthesized-audio cue tables, as pure data. Ported from
/// `src/game/sounds.ts` — the voice tables and scheduling constants only.
/// The Web Audio plumbing (context priming, the sound preference, playback)
/// stays behind; an AVAudioEngine player is built from this file alone.
///
/// Nothing is loaded from disk: every sound is a handful of oscillators drawn
/// on the fly.
///
/// The five that play while a game is running are all short — under a third
/// of a second — so a fast player never hears one land on top of the last:
///
///  - `tick`     — the last few seconds before an Endless round deals its tiles.
///  - `deal`     — tiles arriving in your own pile, in any mode.
///  - `attack`   — the same thing, but sent by a Battle rival: lower and
///                 falling, so incoming trouble never sounds like a gift.
///  - `commit`   — a word going down on the board.
///  - `overflow` — the loose pile has just gone over the limit. A warning, not
///                 a verdict: the round's clock is now the deadline to dig under.
///
/// The two that end a game may take their time, since nothing follows them:
///
///  - `lose`     — buried, or out of time. Four notes falling away.
///  - `win`      — a multiplayer game taken. The same shape climbing.
///
/// ## How a player renders one sound
///
/// Playing cue `name` at engine time `now` means, for each `Blip` in
/// `soundVoices[name]`, with `start = now + SOUND_SCHEDULE_OFFSET_SECONDS`,
/// `from = start + blip.at` and `until = from + blip.dur`:
///
///  1. Run one oscillator of `blip.type` at `blip.freq` Hz from `from`.
///     When `blip.to` is set, ramp the frequency **exponentially** from
///     `blip.freq` to `blip.to` across `[from, until]`
///     (Web Audio's `exponentialRampToValueAtTime`).
///  2. Shape its amplitude — ramped in and out rather than switched, because
///     a wave that starts at full volume clicks, and one that stops there
///     clicks again: gain 0 at `from`, a **linear** ramp up to `blip.gain` by
///     `from + BLIP_ATTACK_SECONDS`, then an **exponential** decay down to
///     `BLIP_DECAY_FLOOR` at `until`.
///  3. Stop the oscillator at `until + BLIP_STOP_PADDING_SECONDS`, leaving
///     room for the decay's tail.

/// Oscillator shape, mirroring the Web Audio `OscillatorType` values the TS
/// table uses.
public enum Waveform: String {
    case sine, square, sawtooth, triangle
}

/// One oscillator's worth of a sound.
public struct Blip: Equatable {
    /// Hz to start at.
    public let freq: Double
    /// Hz to slide to across the blip, when it slides at all. The slide is an
    /// exponential ramp (TS: `exponentialRampToValueAtTime`), so it is always
    /// a nonzero target.
    public let to: Double?
    /// Seconds after the sound's start that this blip begins.
    public let at: Double
    /// How long it rings, in seconds.
    public let dur: Double
    /// Peak loudness, 0–1. Kept low: these play over a game, not as one.
    public let gain: Double
    /// Oscillator shape. The TS field is optional and defaults to `'sine'`
    /// at play time (`blip.type ?? 'sine'`); the default is baked in here.
    public let type: Waveform

    public init(
        freq: Double,
        to: Double? = nil,
        at: Double,
        dur: Double,
        gain: Double,
        type: Waveform = .sine
    ) {
        self.freq = freq
        self.to = to
        self.at = at
        self.dur = dur
        self.gain = gain
        self.type = type
    }
}

/// The cue names — TS `SoundName`.
public enum GameSound: String, CaseIterable {
    case tick, deal, attack, commit, overflow, lose, win
}

// MARK: - Envelope and scheduling constants
//
// The TS player writes these as inline literals in `playSound`; they are the
// other half of the sound's identity, so they get names here.

/// Seconds of linear gain ramp from 0 up to the blip's `gain` at its start.
/// TS: `amp.gain.linearRampToValueAtTime(blip.gain, from + 0.008)`. Without
/// it, a wave that starts at full volume clicks.
public let BLIP_ATTACK_SECONDS = 0.008

/// Where the exponential decay lands: the gain ramps exponentially from the
/// blip's peak down to this floor at `from + dur`. TS:
/// `amp.gain.exponentialRampToValueAtTime(0.0001, until)`. Exponential ramps
/// can't reach zero, so this near-silence stands in for it; a player may snap
/// to 0 afterwards.
public let BLIP_DECAY_FLOOR = 0.0001

/// Seconds between "now" and the sound's scheduled start — a hair in the
/// future, because scheduling at exactly the current time can clip the attack
/// on an audio engine that's still spinning up. TS:
/// `const start = audio.currentTime + 0.01`.
public let SOUND_SCHEDULE_OFFSET_SECONDS = 0.01

/// Seconds past a blip's end (`at + dur`) before its oscillator is stopped,
/// leaving room for the decay's tail. TS: `osc.stop(until + 0.02)`.
public let BLIP_STOP_PADDING_SECONDS = 0.02

// MARK: - Voice tables

/// The cue tables — TS `VOICES`, values verbatim from `src/game/sounds.ts`.
public let soundVoices: [GameSound: [Blip]] = [
    // Dry, high and quiet — five of these count a round down without nagging.
    .tick: [
        Blip(freq: 1040, at: 0, dur: 0.035, gain: 0.05, type: .square),
    ],
    // Tiles landing: three rising notes, light and quick.
    .deal: [
        Blip(freq: 523, at: 0, dur: 0.09, gain: 0.12, type: .triangle),
        Blip(freq: 659, at: 0.055, dur: 0.09, gain: 0.12, type: .triangle),
        Blip(freq: 784, at: 0.11, dur: 0.16, gain: 0.12, type: .triangle),
    ],
    // Tiles landing on you: the same idea inverted — low, falling, and reedy.
    .attack: [
        Blip(freq: 330, to: 145, at: 0, dur: 0.3, gain: 0.14, type: .sawtooth),
        Blip(freq: 220, to: 98, at: 0.05, dur: 0.3, gain: 0.09, type: .square),
    ],
    // A word going down: two notes close enough together to read as one click.
    .commit: [
        Blip(freq: 660, at: 0, dur: 0.05, gain: 0.13, type: .triangle),
        Blip(freq: 990, at: 0.035, dur: 0.1, gain: 0.1, type: .triangle),
    ],
    // Over the limit: a two-tone alarm, the second note lower than the first.
    // Nagging enough to look up at, and plainly not the sound of losing.
    .overflow: [
        Blip(freq: 466, at: 0, dur: 0.11, gain: 0.15, type: .square),
        Blip(freq: 370, at: 0.13, dur: 0.16, gain: 0.15, type: .square),
    ],
    // Four notes falling away, the last one left ringing.
    .lose: [
        Blip(freq: 392, at: 0, dur: 0.16, gain: 0.14, type: .triangle),
        Blip(freq: 311, at: 0.15, dur: 0.16, gain: 0.14, type: .triangle),
        Blip(freq: 262, at: 0.3, dur: 0.16, gain: 0.14, type: .triangle),
        Blip(freq: 196, at: 0.45, dur: 0.5, gain: 0.15, type: .sawtooth),
    ],
    // The same shape climbing, and up an octave by the end of it.
    .win: [
        Blip(freq: 523, at: 0, dur: 0.13, gain: 0.13, type: .triangle),
        Blip(freq: 659, at: 0.1, dur: 0.13, gain: 0.13, type: .triangle),
        Blip(freq: 784, at: 0.2, dur: 0.13, gain: 0.13, type: .triangle),
        Blip(freq: 1047, at: 0.3, dur: 0.45, gain: 0.14, type: .triangle),
    ],
]
