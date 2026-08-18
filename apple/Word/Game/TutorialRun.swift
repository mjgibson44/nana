import Foundation
import WordCore

/// The guided lesson's progress: which scripted step is in hand, and how many
/// were skipped rather than played (App.tsx:402–411, 1990–2017).
///
/// Kept as a value type with no board of its own — `GameModel` owns the tiles
/// and asks this what comes next — so the whole script can be walked in tests
/// without a view or a clock.
struct TutorialRun: Equatable {
    /// 1-based, counting past the script: `TUTORIAL_STEPS + 1` means every
    /// word is down and the way out replaces the pile (App.tsx:96–100).
    private(set) var step = 1
    /// How many steps the player skipped instead of playing. A player who
    /// skipped the lot is handed on rather than parked on a finish button.
    private(set) var skips = 0

    static var doneStep: Int { TUTORIAL_STEPS + 1 }

    var isDone: Bool { step >= Self.doneStep }
    var skippedEverything: Bool { skips >= TUTORIAL_STEPS }

    /// The step being worked, or nil once the script is finished.
    var current: TutorialStep? {
        step >= 1 && step <= TUTORIAL_STEPS ? tutorialScript[step - 1] : nil
    }

    /// What the header shows: the count holds at the last step through the
    /// free practice after it (App.tsx:3073–3077).
    var displayStep: Int { min(step, TUTORIAL_STEPS) }

    /// The word this step is asking for, if any.
    var wantedWord: String? { current?.word }

    /// True when this step insists the word be played *through* a gap tile —
    /// typing straight over the board letter is the same word by the wrong
    /// road, and is refused (App.tsx:2064–2081).
    var needsGap: Bool { current?.needsGap ?? false }

    mutating func countSkip() {
        skips += 1
    }

    /// Finish the step in hand. Returns the announcement for the step just
    /// played and the tiles the next one deals — both nil at the end of the
    /// script (App.tsx advanceTutorial, 1990–2017).
    mutating func advance() -> (done: String?, deal: [String]?) {
        let finished = current
        step += 1
        return (finished?.done, current?.tiles)
    }
}
