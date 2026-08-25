import Foundation
import WordCore

/// A battle's clock and deal position, kept apart from the network the same
/// way `SoloSession` is kept apart from SwiftUI: it owns no board, no stream
/// and no transport, so every timing rule is testable on its own.
///
/// Battle's pressure works differently from Solo's. There is no countdown to
/// survive and no round to dig back under by — instead a batch lands in the
/// pile every `BATTLE_DRIP_SECONDS`, growing with the round, and the only
/// losing condition is letting the pile past `BATTLE_PILE_LIMIT`.
///
/// The load-bearing detail is that a drip's size is **pure in its index**
/// (`battleDripTilesAt`), not in the wall clock. Players' clocks drift — they
/// started the round at slightly different instants and may have been
/// backgrounded — but drip *k* is drip *k* on every screen, so everyone draws
/// the same batch from the shared stream and the deals stay identical
/// (App.tsx:1612–1628).
struct BattleRun: Equatable {
    /// When the host's `start` landed here.
    private(set) var startedAt: Date
    /// How many drips have been dealt — the shared stream's position.
    private(set) var dripIndex: Int
    /// When the next batch is due.
    private(set) var nextDripAt: Date

    init(startedAt: Date, dripIndex: Int = 0) {
        self.startedAt = startedAt
        self.dripIndex = dripIndex
        nextDripAt = startedAt.addingTimeInterval(Double(BATTLE_DRIP_SECONDS))
    }

    func elapsed(at now: Date) -> Double {
        max(0, now.timeIntervalSince(startedAt))
    }

    /// Which round the battle is in — rounds one and two are timed, the final
    /// one runs until the field is decided.
    func round(at now: Date) -> Int {
        battleRoundAt(seconds: elapsed(at: now))
    }

    /// Seconds until the next batch lands, for the header's gauge.
    func secondsToNextDrip(at now: Date) -> Int {
        Int(ceil(max(0, nextDripAt.timeIntervalSince(now))))
    }

    /// Handle at most one drip, like Solo's clock: a player returning from a
    /// long background gets one batch and a fresh interval rather than every
    /// batch they missed landing at once. The index still advances by one, so
    /// they stay in step with the shared stream — they are simply behind it,
    /// which is what the deal being index-pure makes safe.
    mutating func advance(at now: Date) -> Int? {
        guard now >= nextDripAt else { return nil }
        let tiles = battleDripTilesAt(dripIndex: dripIndex)
        dripIndex += 1
        nextDripAt = now.addingTimeInterval(Double(BATTLE_DRIP_SECONDS))
        return tiles
    }
}
