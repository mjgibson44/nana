import AVFoundation
import Foundation
import WordCore

#if canImport(UIKit)
import UIKit
#endif

/// Something that can sound the game's cues. The model raises cues; who turns
/// them into audio and haptics is the app layer's business — and a test's
/// recorder implements this in three lines.
@MainActor
protocol GameCueSink: AnyObject {
    func play(_ sound: GameSound)
}

/// The seven cues, pre-rendered to PCM at launch and played through a shared
/// engine (plan §6.5): no audio assets, no real-time synthesis, lower latency
/// than the web ever had. Paired with haptics on iPhone.
@MainActor
final class AudioEngine: GameCueSink {
    private let engine = AVAudioEngine()
    private var players: [GameSound: AVAudioPlayerNode] = [:]
    private var buffers: [GameSound: AVAudioPCMBuffer] = [:]
    private var started = false

    /// Read live so the settings switch takes effect without re-wiring.
    var isSoundEnabled: () -> Bool = { true }
    var isHapticsEnabled: () -> Bool = { true }

    /// Build the graph and render every cue. Cheap enough for launch: the
    /// seven buffers together are well under a second of mono audio.
    func prepare() {
        guard !started else { return }
        started = true

        configureSession()

        let format = AVAudioFormat(
            standardFormatWithSampleRate: BlipSynth.sampleRate, channels: 1)
        guard let format else { return }

        for sound in GameSound.allCases {
            guard let blips = soundVoices[sound] else { continue }
            let samples = BlipSynth.render(blips)
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                let channel = buffer.floatChannelData?[0]
            else { continue }
            for (index, sample) in samples.enumerated() { channel[index] = sample }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            buffers[sound] = buffer

            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players[sound] = player
        }

        do {
            try engine.start()
            for player in players.values { player.play() }
        } catch {
            // No audio device (CI, a locked-down Mac): the game plays silently.
            started = false
        }
    }

    func play(_ sound: GameSound) {
        haptic(for: sound)
        guard isSoundEnabled() else { return }
        prepare()
        guard started, let player = players[sound], let buffer = buffers[sound] else { return }
        // `.interrupts` so a rapid-fire cue restarts rather than queueing —
        // the web's oscillators likewise never pile up.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    /// Sound cues doubled as feel on iPhone (plan §6.5). Cheap generators
    /// rather than Core Haptics patterns: the two long cues are the only ones
    /// that would benefit from a custom pattern, and they end the game.
    private func haptic(for sound: GameSound) {
        #if os(iOS)
        guard isHapticsEnabled() else { return }
        switch sound {
        case .commit:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .deal:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .attack:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .overflow:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .lose:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .win:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .tick:
            // A once-a-second buzz for the last three seconds would be
            // nagging in the hand; the tick stays audio-only.
            break
        }
        #endif
    }

    /// Ambient: a word game should never duck the player's podcast (§6.5).
    private func configureSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Non-fatal: playback still works for most configurations.
        }
        #endif
    }
}
