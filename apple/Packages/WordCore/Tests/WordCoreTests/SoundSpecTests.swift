import Testing
@testable import WordCore

/// Table-integrity tests for `SoundSpec.swift`. There is no vitest suite for
/// `src/game/sounds.ts` (its behavior is Web Audio playback); these pin the
/// ported data against the TS `VOICES` table and the inline scheduling
/// literals in `playSound`.

@Suite("SoundSpec: voice table") struct SoundSpecVoiceTable {
    @Test("has a voice for all seven cues")
    func hasAVoiceForAllSevenCues() {
        #expect(GameSound.allCases.count == 7)
        #expect(soundVoices.count == 7)
        for sound in GameSound.allCases {
            let blips = soundVoices[sound]
            #expect(blips != nil, "missing voice for \(sound)")
            #expect((blips?.isEmpty ?? true) == false, "empty voice for \(sound)")
        }
    }

    @Test("keeps each cue's blip count from the TS table")
    func keepsEachCuesBlipCountFromTheTSTable() {
        let expected: [GameSound: Int] = [
            .tick: 1,
            .deal: 3,
            .attack: 2,
            .commit: 2,
            .overflow: 2,
            .lose: 4,
            .win: 4,
        ]
        for (sound, count) in expected {
            #expect(soundVoices[sound]?.count == count, "\(sound)")
        }
    }
}

@Suite("SoundSpec: exact blip values") struct SoundSpecExactBlipValues {
    @Test("tick is a single dry high square blip")
    func tickIsASingleDryHighSquareBlip() throws {
        let tick = try #require(soundVoices[.tick])
        #expect(tick == [Blip(freq: 1040, at: 0, dur: 0.035, gain: 0.05, type: .square)])
    }

    @Test("deal starts at C5 and ends on a longer G5")
    func dealStartsAtC5AndEndsOnALongerG5() throws {
        let deal = try #require(soundVoices[.deal])
        #expect(deal.first == Blip(freq: 523, at: 0, dur: 0.09, gain: 0.12, type: .triangle))
        #expect(deal.last == Blip(freq: 784, at: 0.11, dur: 0.16, gain: 0.12, type: .triangle))
    }

    @Test("attack is two falling glides, sawtooth over square")
    func attackIsTwoFallingGlidesSawtoothOverSquare() throws {
        let attack = try #require(soundVoices[.attack])
        #expect(attack.first == Blip(freq: 330, to: 145, at: 0, dur: 0.3, gain: 0.14, type: .sawtooth))
        #expect(attack.last == Blip(freq: 220, to: 98, at: 0.05, dur: 0.3, gain: 0.09, type: .square))
    }

    @Test("commit is two close triangle notes")
    func commitIsTwoCloseTriangleNotes() throws {
        let commit = try #require(soundVoices[.commit])
        #expect(commit.first == Blip(freq: 660, at: 0, dur: 0.05, gain: 0.13, type: .triangle))
        #expect(commit.last == Blip(freq: 990, at: 0.035, dur: 0.1, gain: 0.1, type: .triangle))
    }

    @Test("overflow drops from its first tone to a lower second")
    func overflowDropsFromItsFirstToneToALowerSecond() throws {
        let overflow = try #require(soundVoices[.overflow])
        #expect(overflow.first == Blip(freq: 466, at: 0, dur: 0.11, gain: 0.15, type: .square))
        #expect(overflow.last == Blip(freq: 370, at: 0.13, dur: 0.16, gain: 0.15, type: .square))
    }

    @Test("lose falls from G4 to a long sawtooth G3")
    func loseFallsFromG4ToALongSawtoothG3() throws {
        let lose = try #require(soundVoices[.lose])
        #expect(lose.first == Blip(freq: 392, at: 0, dur: 0.16, gain: 0.14, type: .triangle))
        #expect(lose.last == Blip(freq: 196, at: 0.45, dur: 0.5, gain: 0.15, type: .sawtooth))
    }

    @Test("win climbs from C5 to a long C6")
    func winClimbsFromC5ToALongC6() throws {
        let win = try #require(soundVoices[.win])
        #expect(win.first == Blip(freq: 523, at: 0, dur: 0.13, gain: 0.13, type: .triangle))
        #expect(win.last == Blip(freq: 1047, at: 0.3, dur: 0.45, gain: 0.14, type: .triangle))
    }
}

@Suite("SoundSpec: table invariants") struct SoundSpecTableInvariants {
    @Test("every gain is in (0, 1]")
    func everyGainIsInZeroExclusiveToOne() {
        for (sound, blips) in soundVoices {
            for blip in blips {
                #expect(blip.gain > 0 && blip.gain <= 1, "\(sound): gain \(blip.gain)")
            }
        }
    }

    @Test("every duration is positive")
    func everyDurationIsPositive() {
        for (sound, blips) in soundVoices {
            for blip in blips {
                #expect(blip.dur > 0, "\(sound): dur \(blip.dur)")
            }
        }
    }

    @Test("offsets start at zero and ascend within each cue")
    func offsetsStartAtZeroAndAscendWithinEachCue() {
        // Every cue in the TS table starts its first blip at 0 and lists the
        // rest in strictly ascending `at` order.
        for (sound, blips) in soundVoices {
            #expect(blips.first?.at == 0, "\(sound): first blip not at 0")
            for blip in blips {
                #expect(blip.at >= 0, "\(sound): negative offset \(blip.at)")
            }
            for i in 1..<blips.count {
                #expect(blips[i].at > blips[i - 1].at, "\(sound): offsets not ascending at index \(i)")
            }
        }
    }

    @Test("every glide target is positive and below its start")
    func everyGlideTargetIsPositiveAndBelowItsStart() {
        // Exponential frequency ramps can't pass through zero, and every TS
        // glide falls — attack is the only cue that slides at all.
        for (sound, blips) in soundVoices {
            for blip in blips {
                guard let to = blip.to else { continue }
                #expect(sound == .attack, "\(sound): unexpected glide")
                #expect(to > 0, "\(sound): glide target \(to)")
                #expect(to < blip.freq, "\(sound): glide rises \(blip.freq) -> \(to)")
            }
        }
    }
}

@Suite("SoundSpec: envelope constants") struct SoundSpecEnvelopeConstants {
    @Test("keeps the playSound scheduling literals")
    func keepsThePlaySoundSchedulingLiterals() {
        #expect(BLIP_ATTACK_SECONDS == 0.008)
        #expect(BLIP_DECAY_FLOOR == 0.0001)
        #expect(SOUND_SCHEDULE_OFFSET_SECONDS == 0.01)
        #expect(BLIP_STOP_PADDING_SECONDS == 0.02)
    }
}
