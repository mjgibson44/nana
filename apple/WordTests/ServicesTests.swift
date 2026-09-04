import WordCore
import XCTest

@testable import Word

/// The synthesized cue set (plan §6.5): the seven blip tables become PCM with
/// no assets, so what's worth pinning is the envelope's shape and the buffer's
/// length rather than any particular sample.
final class BlipSynthTests: XCTestCase {
    func testEveryCueRendersAudibleSamples() {
        for sound in GameSound.allCases {
            guard let blips = soundVoices[sound] else {
                XCTFail("\(sound.rawValue) has no blip table")
                continue
            }
            let samples = BlipSynth.render(blips)
            XCTAssertFalse(samples.isEmpty, "\(sound.rawValue) rendered nothing")
            XCTAssertTrue(
                samples.allSatisfy { $0.isFinite }, "\(sound.rawValue) produced non-finite samples")

            let peak = samples.map(abs).max() ?? 0
            // Loud enough to hear, and quiet enough never to clip: these play
            // over a game, not as one.
            XCTAssertGreaterThan(peak, 0.01, "\(sound.rawValue) is inaudible")
            XCTAssertLessThanOrEqual(peak, 1.0, "\(sound.rawValue) clips")
        }
    }

    func testBufferLengthCoversTheLastBlipPlusStopPadding() {
        let blips = [
            Blip(freq: 440, to: nil, at: 0, dur: 0.1, gain: 0.2, type: .sine),
            Blip(freq: 880, to: nil, at: 0.3, dur: 0.2, gain: 0.2, type: .sine),
        ]
        // Last blip ends at 0.5s, plus the web's 0.02s stop padding.
        XCTAssertEqual(BlipSynth.duration(of: blips), 0.5 + BLIP_STOP_PADDING_SECONDS, accuracy: 1e-9)
        let samples = BlipSynth.render(blips, sampleRate: 1_000)
        XCTAssertEqual(samples.count, Int((0.5 + BLIP_STOP_PADDING_SECONDS) * 1_000))
    }

    func testEnvelopeAttacksLinearlyThenDecaysToTheFloor() {
        let blip = Blip(freq: 440, to: nil, at: 0, dur: 0.2, gain: 0.4, type: .sine)
        // Starts silent, so the wave never begins at full volume (which clicks).
        XCTAssertEqual(BlipSynth.envelope(blip, at: 0), 0, accuracy: 1e-9)
        // Peaks exactly at the end of the 8ms attack.
        XCTAssertEqual(
            BlipSynth.envelope(blip, at: BLIP_ATTACK_SECONDS), 0.4, accuracy: 1e-9)
        XCTAssertEqual(
            BlipSynth.envelope(blip, at: BLIP_ATTACK_SECONDS / 2), 0.2, accuracy: 1e-9)
        // Then decays to the floor rather than stopping hard.
        XCTAssertEqual(BlipSynth.envelope(blip, at: 0.2), BLIP_DECAY_FLOOR, accuracy: 1e-6)
        // Monotonically down through the decay.
        let mid = BlipSynth.envelope(blip, at: 0.1)
        XCTAssertLessThan(mid, 0.4)
        XCTAssertGreaterThan(mid, BLIP_DECAY_FLOOR)
        // Nothing outside the blip's own window.
        XCTAssertEqual(BlipSynth.envelope(blip, at: 0.25), 0)
    }

    func testGlidingBlipStaysFinite() {
        // The attack cue slides 330 → 145Hz; a naive phase computation goes
        // discontinuous at the ends.
        let blip = Blip(freq: 330, to: 145, at: 0, dur: 0.3, gain: 0.14, type: .sawtooth)
        let samples = BlipSynth.render([blip], sampleRate: 8_000)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite })
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01)
    }
}

/// Preferences ride WordCore's storage helpers, so the web's keys and its
/// "garbage falls back to defaults" semantics carry over (plan §9.1).
@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsMatchTheWebAndPersistUnderTheSameKeys() {
        let store = MemoryStore()
        let settings = AppSettings(store: store)
        // Sound and haptics are on until turned off.
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertTrue(settings.hapticsEnabled)

        settings.soundEnabled = false
        settings.hapticsEnabled = false
        XCTAssertEqual(store.get("nana.sound.v1"), "off")
        XCTAssertEqual(store.get("nana.haptics.v1"), "off")

        // A fresh instance over the same store reads it all back.
        let reloaded = AppSettings(store: store)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertFalse(reloaded.hapticsEnabled)
    }

    func testThePaceRoundTrips() {
        let store = MemoryStore()
        let settings = AppSettings(store: store)
        XCTAssertEqual(settings.pace, .regular)

        settings.pace = .fast

        let reloaded = AppSettings(store: store)
        XCTAssertEqual(reloaded.pace, .fast)
    }

    func testFinishedGamesRecordToStats() {
        let store = MemoryStore()
        let settings = AppSettings(store: store)
        XCTAssertEqual(settings.stats().gamesPlayed, 0)
        settings.record(score: 42, words: 7)
        settings.record(score: 13, words: 3)
        let stats = AppSettings(store: store).stats()
        XCTAssertEqual(stats.gamesPlayed, 2)
        XCTAssertEqual(stats.recent.count, 2)
        XCTAssertTrue(stats.recent.contains { $0.score == 42 && $0.words == 7 })
    }
}
