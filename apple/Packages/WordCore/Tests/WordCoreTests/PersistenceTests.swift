import Testing
@testable import WordCore

/// Port of `src/game/__tests__/setups.test.ts`, plus suites for the stats,
/// onboarding and sound-preference halves of `Persistence.swift`, pinning the
/// same defensive-parsing rules the TS modules live by.

/// The vitest suite's fake localStorage, split into its two states. The fake
/// kept a `Map | null`, where `null` made every call throw the way a
/// locked-down browser does; `KeyValueStore` bakes that in instead, so the
/// blocked state is a store whose reads miss and whose writes never land.
private final class MemoryStore: KeyValueStore {
    var values: [String: String] = [:]
    func get(_ key: String) -> String? { values[key] }
    func set(_ key: String, _ value: String) { values[key] = value }
    func remove(_ key: String) { values[key] = nil }
}

private final class BlockedStore: KeyValueStore {
    func get(_ key: String) -> String? { nil }
    func set(_ key: String, _ value: String) {}
    func remove(_ key: String) {}
}

// MARK: - setups.test.ts

@Suite("Persistence: setups, defaults") struct PersistenceSetupsDefaults {
    @Test("opens Solo at the regular pace")
    func opensSoloAtTheRegularPace() {
        #expect(DEFAULT_SOLO == SoloSetup(pace: .regular))
    }

    @Test("are what a player with nothing stored gets")
    func areWhatAPlayerWithNothingStoredGets() {
        #expect(loadSoloSetup(from: MemoryStore()) == DEFAULT_SOLO)
    }
}

@Suite("Persistence: setups, round trip") struct PersistenceSetupsRoundTrip {
    @Test("gives a saved Solo setup back")
    func givesASavedSoloSetupBack() {
        let store = MemoryStore()
        saveSoloSetup(SoloSetup(pace: .fast), to: store)
        #expect(loadSoloSetup(from: store) == SoloSetup(pace: .fast))
    }

    @Test("keeps the last save, not the first")
    func keepsTheLastSaveNotTheFirst() {
        let store = MemoryStore()
        saveSoloSetup(SoloSetup(pace: .fast), to: store)
        saveSoloSetup(SoloSetup(pace: .regular), to: store)
        #expect(loadSoloSetup(from: store).pace == .regular)
    }

    @Test("writes the exact bytes the web build stores")
    func writesTheExactBytesTheWebBuildStores() {
        let store = MemoryStore()
        saveSoloSetup(SoloSetup(pace: .fast), to: store)
        #expect(store.values["nana.setup.solo.v1"] == "{\"pace\":\"fast\"}")
    }
}

@Suite("Persistence: setups, untrustworthy storage") struct PersistenceSetupsUntrustworthyStorage {
    @Test("falls back to the defaults for anything that isn’t JSON")
    func fallsBackToTheDefaultsForAnythingThatIsntJSON() {
        let store = MemoryStore()
        store.set("nana.setup.solo.v1", "not json {")
        #expect(loadSoloSetup(from: store) == DEFAULT_SOLO)
    }

    @Test("falls back for JSON that isn’t an object")
    func fallsBackForJSONThatIsntAnObject() {
        let store = MemoryStore()
        store.set("nana.setup.solo.v1", "[1, 2, 3]")
        #expect(loadSoloSetup(from: store) == DEFAULT_SOLO)
    }

    @Test("replaces a pace it can’t use")
    func replacesAPaceItCantUse() {
        let store = MemoryStore()
        store.set("nana.setup.solo.v1", "{\"pace\":\"ludicrous\"}")
        #expect(loadSoloSetup(from: store) == DEFAULT_SOLO)
    }

    @Test("reads the defaults when storage is blocked outright")
    func readsTheDefaultsWhenStorageIsBlockedOutright() {
        #expect(loadSoloSetup(from: BlockedStore()) == DEFAULT_SOLO)
    }

    @Test("swallows a write that can’t land")
    func swallowsAWriteThatCantLand() {
        // `saveSoloSetup` is non-throwing by signature; the blocked store just
        // drops the write, and the next read still has the defaults.
        let store = BlockedStore()
        saveSoloSetup(DEFAULT_SOLO, to: store)
        #expect(loadSoloSetup(from: store) == DEFAULT_SOLO)
    }
}

// MARK: - stats.ts

@Suite("Persistence: loadStats") struct PersistenceLoadStats {
    @Test("starts from zero with nothing stored")
    func startsFromZeroWithNothingStored() {
        #expect(loadStats(from: MemoryStore()) == Stats(gamesPlayed: 0, recent: []))
    }

    @Test("reads back a stored history, newest first")
    func readsBackAStoredHistoryNewestFirst() {
        let store = MemoryStore()
        store.set(
            "nana.stats.v1",
            "{\"gamesPlayed\":4,\"recent\":[{\"score\":90,\"words\":8,\"at\":1700000000000},"
                + "{\"score\":10,\"words\":2,\"at\":1600000000000}]}"
        )
        let stats = loadStats(from: store)
        #expect(stats.gamesPlayed == 4)
        #expect(stats.recent == [
            GameRecord(score: 90, words: 8, at: 1_700_000_000_000),
            GameRecord(score: 10, words: 2, at: 1_600_000_000_000),
        ])
    }

    @Test("starts from zero on garbage JSON")
    func startsFromZeroOnGarbageJSON() {
        let store = MemoryStore()
        store.set("nana.stats.v1", "not json {")
        #expect(loadStats(from: store) == Stats(gamesPlayed: 0, recent: []))
    }

    @Test("starts from zero on an empty string")
    func startsFromZeroOnAnEmptyString() {
        let store = MemoryStore()
        store.set("nana.stats.v1", "")
        #expect(loadStats(from: store) == Stats(gamesPlayed: 0, recent: []))
    }

    @Test("starts from zero on JSON that isn’t an object")
    func startsFromZeroOnJSONThatIsntAnObject() {
        for raw in ["[1, 2, 3]", "42", "\"stats\"", "null"] {
            let store = MemoryStore()
            store.set("nana.stats.v1", raw)
            #expect(loadStats(from: store) == Stats(gamesPlayed: 0, recent: []), "raw: \(raw)")
        }
    }

    @Test("drops records that aren’t objects with numeric fields")
    func dropsRecordsThatArentObjectsWithNumericFields() {
        let store = MemoryStore()
        store.set(
            "nana.stats.v1",
            "{\"gamesPlayed\":9,\"recent\":[7,\"x\",null,[],"
                + "{\"score\":1,\"words\":1},"
                + "{\"score\":\"1\",\"words\":1,\"at\":1},"
                + "{\"score\":true,\"words\":1,\"at\":1},"
                + "{\"score\":5,\"words\":2,\"at\":3}]}"
        )
        let stats = loadStats(from: store)
        #expect(stats.recent == [GameRecord(score: 5, words: 2, at: 3)])
        // The survivors still trust the stored total — 9 covers one record.
        #expect(stats.gamesPlayed == 9)
    }

    @Test("ignores a recent that isn’t an array")
    func ignoresARecentThatIsntAnArray() {
        let store = MemoryStore()
        store.set("nana.stats.v1", "{\"gamesPlayed\":5,\"recent\":\"nope\"}")
        #expect(loadStats(from: store) == Stats(gamesPlayed: 5, recent: []))
    }

    @Test("floors a stored gamesPlayed that covers recent")
    func floorsAStoredGamesPlayedThatCoversRecent() {
        let store = MemoryStore()
        store.set("nana.stats.v1", "{\"gamesPlayed\":7.9,\"recent\":[{\"score\":5,\"words\":2,\"at\":3}]}")
        #expect(loadStats(from: store).gamesPlayed == 7)
    }

    @Test("counts recent instead when gamesPlayed is smaller, negative or not a number")
    func countsRecentInsteadWhenGamesPlayedIsUnusable() {
        let one = "{\"score\":5,\"words\":2,\"at\":3}"
        for played in ["0", "1", "-3", "\"12\"", "true", "null"] {
            let store = MemoryStore()
            store.set("nana.stats.v1", "{\"gamesPlayed\":\(played),\"recent\":[\(one),\(one)]}")
            #expect(loadStats(from: store).gamesPlayed == 2, "gamesPlayed: \(played)")
        }
    }

    @Test("counts recent when gamesPlayed is absent")
    func countsRecentWhenGamesPlayedIsAbsent() {
        let store = MemoryStore()
        store.set("nana.stats.v1", "{\"recent\":[{\"score\":5,\"words\":2,\"at\":3}]}")
        #expect(loadStats(from: store) == Stats(gamesPlayed: 1, recent: [GameRecord(score: 5, words: 2, at: 3)]))
    }

    @Test("starts from zero when storage is blocked")
    func startsFromZeroWhenStorageIsBlocked() {
        #expect(loadStats(from: BlockedStore()) == Stats(gamesPlayed: 0, recent: []))
    }
}

@Suite("Persistence: recordGame") struct PersistenceRecordGame {
    @Test("counts and keeps a first game")
    func countsAndKeepsAFirstGame() {
        let store = MemoryStore()
        let record = GameRecord(score: 42, words: 7, at: 1_700_000_000_000)
        let stats = recordGame(record, in: store)
        #expect(stats == Stats(gamesPlayed: 1, recent: [record]))
        #expect(loadStats(from: store) == stats)
    }

    @Test("prepends — newest first")
    func prependsNewestFirst() {
        let store = MemoryStore()
        _ = recordGame(GameRecord(score: 1, words: 1, at: 1000), in: store)
        let stats = recordGame(GameRecord(score: 2, words: 2, at: 2000), in: store)
        #expect(stats.gamesPlayed == 2)
        #expect(stats.recent.map { $0.at } == [2000, 1000])
    }

    @Test("writes the exact JSON shape the web build stores")
    func writesTheExactJSONShapeTheWebBuildStores() {
        let store = MemoryStore()
        _ = recordGame(GameRecord(score: 12, words: 3, at: 1_700_000_000_000), in: store)
        #expect(store.values["nana.stats.v1"]
            == "{\"gamesPlayed\":1,\"recent\":[{\"score\":12,\"words\":3,\"at\":1700000000000}]}")
    }

    @Test("caps recent at RECENT_LIMIT but keeps counting gamesPlayed")
    func capsRecentAtRecentLimitButKeepsCountingGamesPlayed() {
        #expect(RECENT_LIMIT == 30)
        let store = MemoryStore()
        var last = Stats(gamesPlayed: 0, recent: [])
        for i in 0...RECENT_LIMIT {
            last = recordGame(GameRecord(score: i, words: i, at: Double(i)), in: store)
        }
        #expect(last.gamesPlayed == RECENT_LIMIT + 1)
        #expect(last.recent.count == RECENT_LIMIT)
        // Newest first; the very first game fell off the end.
        #expect(last.recent.first?.at == Double(RECENT_LIMIT))
        #expect(last.recent.last?.at == 1)
        #expect(loadStats(from: store) == last)
    }

    @Test("keeps counting above a stored total that outruns recent")
    func keepsCountingAboveAStoredTotalThatOutrunsRecent() {
        let store = MemoryStore()
        store.set("nana.stats.v1", "{\"gamesPlayed\":100,\"recent\":[]}")
        let stats = recordGame(GameRecord(score: 5, words: 2, at: 3), in: store)
        #expect(stats.gamesPlayed == 101)
        #expect(stats.recent.count == 1)
    }

    @Test("still returns the finished game when the write can’t land")
    func stillReturnsTheFinishedGameWhenTheWriteCantLand() {
        let store = BlockedStore()
        let record = GameRecord(score: 9, words: 4, at: 1234)
        let stats = recordGame(record, in: store)
        #expect(stats == Stats(gamesPlayed: 1, recent: [record]))
        // …but nothing stuck: the next read starts from zero again.
        #expect(loadStats(from: store) == Stats(gamesPlayed: 0, recent: []))
    }
}

// MARK: - onboarding.ts

@Suite("Persistence: onboarding") struct PersistenceOnboarding {
    @Test("the tutorial reads as unseen at first")
    func theTutorialReadsAsUnseenAtFirst() {
        #expect(!hasSeenTutorial(in: MemoryStore()))
    }

    @Test("marking the tutorial sticks, storing a timestamp string")
    func markingTheTutorialSticksStoringATimestampString() {
        let store = MemoryStore()
        markTutorialSeen(in: store)
        #expect(hasSeenTutorial(in: store))
        // The TS writes `String(Date.now())` — Unix ms, not seconds.
        let value = store.values["nana.tutorial.v1"]
        #expect((value.flatMap { Double($0) } ?? 0) > 1.7e12)
    }

    @Test("any stored value counts as seen — presence is the flag")
    func anyStoredValueCountsAsSeen() {
        let store = MemoryStore()
        store.set("nana.tutorial.v1", "whenever")
        #expect(hasSeenTutorial(in: store))
    }

    @Test("doors read as unseen at first, and one at a time")
    func doorsReadAsUnseenAtFirstAndOneAtATime() {
        let store = MemoryStore()
        #expect(!hasSeenDoor(.solo, in: store))
        #expect(!hasSeenDoor(.battle, in: store))
        markDoorSeen(.solo, in: store)
        #expect(hasSeenDoor(.solo, in: store))
        #expect(!hasSeenDoor(.battle, in: store))
    }

    @Test("stores seen doors as a comma-separated list of raw values")
    func storesSeenDoorsAsACommaSeparatedListOfRawValues() {
        let store = MemoryStore()
        markDoorSeen(.solo, in: store)
        markDoorSeen(.battle, in: store)
        #expect(store.values["nana.doors.v1"] == "solo,battle")
        #expect(hasSeenDoor(.solo, in: store))
        #expect(hasSeenDoor(.battle, in: store))
    }

    @Test("reads a web-written doors list and appends to it")
    func readsAWebWrittenDoorsListAndAppendsToIt() {
        let store = MemoryStore()
        store.set("nana.doors.v1", "battle")
        #expect(hasSeenDoor(.battle, in: store))
        #expect(!hasSeenDoor(.solo, in: store))
        markDoorSeen(.solo, in: store)
        #expect(store.values["nana.doors.v1"] == "battle,solo")
    }

    @Test("doesn’t duplicate a door marked twice")
    func doesntDuplicateADoorMarkedTwice() {
        let store = MemoryStore()
        markDoorSeen(.solo, in: store)
        markDoorSeen(.solo, in: store)
        #expect(store.values["nana.doors.v1"] == "solo")
    }

    @Test("blocked storage reads as not seen and swallows marks")
    func blockedStorageReadsAsNotSeenAndSwallowsMarks() {
        let store = BlockedStore()
        #expect(!hasSeenTutorial(in: store))
        #expect(!hasSeenDoor(.solo, in: store))
        markTutorialSeen(in: store)
        markDoorSeen(.solo, in: store)
        // A failed write simply doesn't stick — both will be offered again.
        #expect(!hasSeenTutorial(in: store))
        #expect(!hasSeenDoor(.solo, in: store))
    }
}

// MARK: - sounds.ts (the pref only)

@Suite("Persistence: sound preference") struct PersistenceSoundPreference {
    @Test("sound is on until it’s turned off")
    func soundIsOnUntilItsTurnedOff() {
        #expect(isSoundEnabled(in: MemoryStore()))
    }

    @Test("only the exact value \"off\" silences it")
    func onlyTheExactValueOffSilencesIt() {
        let store = MemoryStore()
        store.set("nana.sound.v1", "off")
        #expect(!isSoundEnabled(in: store))
        for value in ["on", "OFF", "false", "0", ""] {
            store.set("nana.sound.v1", value)
            #expect(isSoundEnabled(in: store), "value: \(value)")
        }
    }

    @Test("round-trips the toggle, writing \"on\" and \"off\"")
    func roundTripsTheToggleWritingOnAndOff() {
        let store = MemoryStore()
        setSoundEnabled(false, in: store)
        #expect(store.values["nana.sound.v1"] == "off")
        #expect(!isSoundEnabled(in: store))
        setSoundEnabled(true, in: store)
        #expect(store.values["nana.sound.v1"] == "on")
        #expect(isSoundEnabled(in: store))
    }

    @Test("plays sound anyway when storage is blocked")
    func playsSoundAnywayWhenStorageIsBlocked() {
        let store = BlockedStore()
        #expect(isSoundEnabled(in: store))
        setSoundEnabled(false, in: store)
        // The choice just won't survive — a blocked write never lands.
        #expect(isSoundEnabled(in: store))
    }
}
