import Foundation
import WordCore

/// A countdown is either tied to wall clock time or frozen with an exact
/// amount remaining. This is the web game's `endsAt` / `remainingMs` model,
/// expressed independently of SwiftUI so pause and expiry behavior stays
/// deterministic under tests and app backgrounding.
enum SoloCountdown: Equatable {
    case running(endsAt: Date)
    case paused(remaining: TimeInterval)

    func remaining(at now: Date) -> TimeInterval {
        switch self {
        case let .running(endsAt): max(0, endsAt.timeIntervalSince(now))
        case let .paused(remaining): max(0, remaining)
        }
    }

    mutating func pause(at now: Date) {
        guard case let .running(endsAt) = self else { return }
        self = .paused(remaining: max(0, endsAt.timeIntervalSince(now)))
    }

    mutating func resume(at now: Date) {
        guard case let .paused(remaining) = self else { return }
        self = .running(endsAt: now.addingTimeInterval(max(0, remaining)))
    }
}

enum SoloPhase: Equatable {
    case initial
    case drip
}

enum SoloEndReason: Equatable {
    case buried
}

/// Cards that briefly cover the board and freeze a Solo countdown.
enum SoloSplash: Equatable {
    case start
    case speedUp(seconds: Int, tiles: Int)
}

enum SoloClockEffect: Equatable {
    case none
    case deal(tiles: Int)
    case buried
}

/// The pressure-clock state machine. It owns no board or random generator;
/// an expiry emits an effect and `GameModel` applies the corresponding deal
/// or freezes the final score.
struct SoloSession: Equatable {
    private(set) var pace: SoloPace
    private(set) var phase: SoloPhase = .initial
    private(set) var dripsElapsed = 0
    private(set) var countdown: SoloCountdown?
    private(set) var paused = false
    private(set) var splash: SoloSplash? = .start
    private(set) var complete = false
    private(set) var endReason: SoloEndReason?

    init(pace: SoloPace, now _: Date) {
        self.pace = pace
        // The opening card is readable content, so the initial clock starts
        // frozen and is released when the card is dismissed.
        countdown = .paused(remaining: Double(endlessInitialSeconds(pace)))
    }

    var clockHeld: Bool { paused || splash != nil }

    func remaining(at now: Date) -> TimeInterval? {
        countdown?.remaining(at: now)
    }

    mutating func dismissSplash(at now: Date) {
        guard splash != nil else { return }
        splash = nil
        normalizeCountdown(at: now)
    }

    mutating func pause(at now: Date) {
        guard !complete, splash == nil, !paused else { return }
        paused = true
        normalizeCountdown(at: now)
    }

    mutating func resume(at now: Date) {
        guard !complete, paused else { return }
        paused = false
        normalizeCountdown(at: now)
    }

    /// Handle at most one expiry. Like the web app, returning from a long
    /// background interval deals one batch and starts a fresh round rather
    /// than replaying every interval that elapsed while suspended.
    mutating func advance(at now: Date, looseTiles: Int) -> SoloClockEffect {
        guard !complete, case let .running(endsAt) = countdown, now >= endsAt else {
            return .none
        }

        // The limit is a deadline, not an instant loss: the player gets the
        // remainder of this drip round to work back down to twenty.
        if phase == .drip, looseTiles > ENDLESS_LOOSE_LIMIT {
            finish(reason: .buried)
            return .buried
        }

        let elapsed = phase == .drip ? dripsElapsed + 1 : 0
        let seconds = endlessDripSeconds(elapsed, pace)
        let tiles = endlessDripTiles(elapsed, pace)
        let spedUp = elapsed > 0
            && (seconds < endlessDripSeconds(elapsed - 1, pace)
                || tiles > endlessDripTiles(elapsed - 1, pace))

        phase = .drip
        dripsElapsed = elapsed
        splash = spedUp ? .speedUp(seconds: seconds, tiles: tiles) : nil
        countdown = clockHeld
            ? .paused(remaining: Double(seconds))
            : .running(endsAt: now.addingTimeInterval(Double(seconds)))
        return .deal(tiles: tiles)
    }

    mutating func finish(reason: SoloEndReason) {
        guard !complete else { return }
        complete = true
        endReason = reason
        countdown = nil
        paused = false
        splash = nil
    }

    private mutating func normalizeCountdown(at now: Date) {
        guard countdown != nil else { return }
        if clockHeld {
            countdown?.pause(at: now)
        } else {
            countdown?.resume(at: now)
        }
    }
}
