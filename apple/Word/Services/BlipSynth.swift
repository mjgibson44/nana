import Foundation
import WordCore

/// Sample-exact synthesis of WordCore's blip tables — the port of the web
/// game's Web Audio graph (`sounds.ts:169–192`) as plain arithmetic, so the
/// seven cues can be pre-rendered once at launch (plan §6.5) and so the
/// envelope is unit-testable without an audio device.
///
/// Per blip, matching the web's node graph exactly:
///
///  - frequency: held at `freq`, or ramped exponentially to `to` across the
///    blip (`exponentialRampToValueAtTime`);
///  - gain: 0 → `gain` linearly over `BLIP_ATTACK_SECONDS`, then exponentially
///    down to `BLIP_DECAY_FLOOR` at the blip's end.
enum BlipSynth {
    static let sampleRate: Double = 44_100

    /// How long a cue's buffer runs: its last blip's end, plus the web's
    /// stop padding so an exponential tail is never clipped mid-decay.
    static func duration(of blips: [Blip]) -> Double {
        (blips.map { $0.at + $0.dur }.max() ?? 0) + BLIP_STOP_PADDING_SECONDS
    }

    /// One cue rendered to mono float samples in −1…1.
    static func render(_ blips: [Blip], sampleRate: Double = sampleRate) -> [Float] {
        let total = duration(of: blips)
        var samples = [Float](repeating: 0, count: max(1, Int(total * sampleRate)))

        for blip in blips {
            let start = Int(blip.at * sampleRate)
            let count = Int(blip.dur * sampleRate)
            guard count > 0 else { continue }
            // Phase is accumulated rather than computed from t, so a gliding
            // frequency stays continuous instead of stepping.
            var phase = 0.0

            for index in 0..<count {
                let sampleIndex = start + index
                guard samples.indices.contains(sampleIndex) else { break }
                let t = Double(index) / sampleRate

                let frequency: Double
                if let to = blip.to, to > 0, blip.freq > 0 {
                    // Web Audio's exponential ramp: geometric interpolation.
                    frequency = blip.freq * pow(to / blip.freq, t / blip.dur)
                } else {
                    frequency = blip.freq
                }

                samples[sampleIndex] += Float(wave(blip.type, phase) * envelope(blip, at: t))
                phase += 2 * Double.pi * frequency / sampleRate
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
            }
        }

        return samples
    }

    /// The web's two-stage envelope: a short linear attack so the wave never
    /// starts at full volume (which clicks), then an exponential decay to a
    /// floor rather than a hard stop (which clicks again).
    static func envelope(_ blip: Blip, at t: Double) -> Double {
        guard t >= 0, t <= blip.dur else { return 0 }
        let attack = min(BLIP_ATTACK_SECONDS, blip.dur)
        if t < attack {
            return attack > 0 ? blip.gain * (t / attack) : blip.gain
        }
        let decay = blip.dur - attack
        guard decay > 0, blip.gain > 0 else { return BLIP_DECAY_FLOOR }
        return blip.gain * pow(BLIP_DECAY_FLOOR / blip.gain, (t - attack) / decay)
    }

    private static func wave(_ type: Waveform, _ phase: Double) -> Double {
        let turn = phase / (2 * Double.pi)
        switch type {
        case .sine:
            return sin(phase)
        case .square:
            return turn < 0.5 ? 1 : -1
        case .sawtooth:
            return 2 * turn - 1
        case .triangle:
            return turn < 0.5 ? (4 * turn - 1) : (3 - 4 * turn)
        }
    }
}
