import SwiftUI

/// The redesign's palette: one dark theme, sampled from the reference
/// mockups. Everything structural is a near-black warm grey; the only colour
/// is the green that marks a word — typed, placed, or a title — the red that
/// says a word isn't one, and the gauge that says how close the pile is to
/// burying you.
enum Palette {
    /// The screen.
    static let bg = Color(hex: 0x151110)
    /// Board cells, idle pile tiles, buttons, the menu.
    static let surface = Color(hex: 0x212121)
    /// A pile tile claimed for the word.
    static let surfaceRaised = Color(hex: 0x454545)
    /// An empty pile slot: barely there, so the 3×10 field reads as a field.
    static let slot = Color(hex: 0x1B1716)
    /// Primary text and lit-up letters.
    static let ink = Color(hex: 0xD4D4D4)
    /// Idle pile letters, labels, icons.
    static let inkSoft = Color(hex: 0x848484)
    /// Disabled controls.
    static let inkFaint = Color(hex: 0x4B4B4B)
    /// A word that reads: green, because green is the answer "yes, that is a
    /// word" — given while it is still being built, not only once it lands.
    static let accent = Color(hex: 0xB6DA97)
    static let accentBg = Color(hex: 0x253F18)
    /// A word held over the board, a step brighter than one already down, so
    /// the thing being aimed reads above the board it is aimed at.
    static let accentRaised = Color(hex: 0x2F5620)
    /// The confirm button: solid green with a dark mark on it. The one "go"
    /// on the screen, and the only place the bright green is a fill.
    static let accentButton = Color(hex: 0x23B626)
    static let accentButtonInk = Color(hex: 0x151110)

    /// A word that isn't a word — in the row while it's being built, and on
    /// the board when it's held somewhere it can't land. As bright against
    /// its dark red as `accent` is against its dark green: it is the same
    /// "here is your word" moment, answered differently.
    static let badInk = Color(hex: 0xFF5C5C)
    static let badBg = Color(hex: 0x5D1F1F)

    // The pile gauge: green while there's room, amber as it fills, red when
    // the next batch could end the game — the reading every progress bar
    // has, in a game where a full bar is the end of it.
    static let gaugeOk = Color(hex: 0x23B626)
    static let gaugeOkTrack = Color(hex: 0x193A16)
    static let gaugeWarn = Color(hex: 0xA66C00)
    static let gaugeWarnTrack = Color(hex: 0x4D3711)
    static let gaugeBad = Color(hex: 0xB73131)
    static let gaugeBadTrack = badBg

    /// Occupy's rivals. Your own tiles are always the word green, because
    /// green means "yours" everywhere else on the screen; each rival gets one
    /// of these, in seat order, so the same player is the same colour on
    /// the board, the bar and the standings. Three, for a room of four.
    static let rivalInks: [Color] = [
        Color(hex: 0x8EC5FF), Color(hex: 0xFFB86B), Color(hex: 0xE0A6FF),
    ]
    static let rivalBgs: [Color] = [
        Color(hex: 0x1B3550), Color(hex: 0x4A2E0F), Color(hex: 0x3D1F55),
    ]
}

/// The colours a seat's tiles wear, as seen from another seat.
struct SeatColors: Equatable {
    var ink: Color
    var fill: Color

    /// You are green; your rivals take the rival colours in seat order,
    /// skipping your own seat so a room of four uses exactly three.
    static func of(seat: Int, viewer: Int?) -> SeatColors {
        guard let viewer, seat != viewer else {
            return seat == viewer || viewer == nil
                ? SeatColors(ink: Palette.accent, fill: Palette.accentBg)
                : rival(seat)
        }
        let rank = seat < viewer ? seat : seat - 1
        return rival(rank)
    }

    private static func rival(_ rank: Int) -> SeatColors {
        let index = max(0, rank) % Palette.rivalInks.count
        return SeatColors(ink: Palette.rivalInks[index], fill: Palette.rivalBgs[index])
    }
}

/// The one spacing system every screen uses: the same margin around the
/// outside, the same gap between sections, the same gap between tiles.
enum Spacing {
    /// Around the outside of every screen.
    static let margin: CGFloat = 16
    /// Between rows and sections.
    static let gap: CGFloat = 16
    /// Between tiles in a row.
    static let tileGap: CGFloat = 4
    /// The pile is eight tiles wide — fewer, bigger tiles than the original
    /// ten, which is what makes them thumb-sized on a phone.
    static let columns = 8
    /// The shuffle button stands to the right of the pile, on its own: it
    /// rearranges the tiles rather than acting on the word, so it doesn't
    /// belong in the row of word actions. One and a half tiles wide, so it
    /// reads as a control and not as a ninth letter.
    static let shuffleTiles: CGFloat = 1.5
    /// Rows the pile always draws, full or not. Eight across by three down is
    /// twenty-four slots, which *is* `PILE_LIMIT`: a full pile looks like the
    /// end because it is the end.
    static let pileRows = 3
    /// Tile size on screens that aren't fitted to the width (home, results).
    static let tile: CGFloat = 32
    static let tileRadius: CGFloat = 3
    /// Buttons are a little shorter than a tile is tall.
    static let buttonHeight: CGFloat = 36
    /// Phone-first: wider screens get the same column, centred.
    static let maxWidth: CGFloat = 520

    /// How wide a pile tile is when `columns` of them, the gap, and the
    /// shuffle button beside them share `width`. Every tile on the game
    /// screen is sized from this, so the word row and the pile stay the same
    /// tiles even though only one of them shares its row.
    static func tileSize(fitting width: CGFloat) -> CGFloat {
        let slots = CGFloat(columns) + shuffleTiles
        return max(20, (width - CGFloat(columns - 1) * tileGap - gap) / slots)
    }

    /// How wide the pile itself draws at that tile size — the other side of
    /// the row is whatever is left for the shuffle button.
    static func pileWidth(tileSize: CGFloat) -> CGFloat {
        CGFloat(columns) * tileSize + CGFloat(columns - 1) * tileGap
    }

    /// The word being built never wraps. Up to the point where `cap`-sized
    /// tiles fill the row it is laid out at that size; past it every tile
    /// shrinks so the whole word stays on one line, and a word long enough
    /// to make the letters small gives up the gaps between tiles first.
    static func wordRow(count: Int, fitting width: CGFloat, cap: CGFloat)
        -> (size: CGFloat, gap: CGFloat)
    {
        guard count > 0, width > 0 else { return (cap, tileGap) }
        let tiles = CGFloat(count)
        func fitted(gap: CGFloat) -> CGFloat { (width - (tiles - 1) * gap) / tiles }
        var gap = tileGap
        var size = fitted(gap: gap)
        if size < cap / 2 {
            gap = 1
            size = fitted(gap: gap)
        }
        return (min(cap, max(6, size)), gap)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
