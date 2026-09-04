import SwiftUI

/// The redesign's palette: one dark theme, sampled from the reference
/// mockups. Everything structural is a near-black warm grey; the only colour
/// is the amber that marks a word — typed, placed, or a title — and the
/// gauge that says how close the pile is to burying you.
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
    /// The word: typed, placed, or a title.
    static let accent = Color(hex: 0xFFA600)
    static let accentBg = Color(hex: 0x4D3711)
    /// The confirm button, a step brighter than a word tile.
    static let accentButton = Color(hex: 0x63450F)

    // The pile gauge: purple while there's room, amber as it fills, red when
    // the next batch could end the game. Purple rather than the usual
    // progress-bar green — good standing is the game's calm state, not a
    // "pass", and green would fight the amber that means "word".
    static let gaugeOk = Color(hex: 0x8023B6)
    static let gaugeOkTrack = Color(hex: 0x3F095B)
    static let gaugeWarn = Color(hex: 0xA66C00)
    static let gaugeWarnTrack = Color(hex: 0x4D3711)
    static let gaugeBad = Color(hex: 0xB73131)
    static let gaugeBadTrack = Color(hex: 0x5D1F1F)

    /// A word that isn't a word, held over the board in red. As bright
    /// against its dark red as `accent` is against its dark amber — it is
    /// the same "here is your word" moment, answered differently.
    static let badInk = Color(hex: 0xFF5C5C)
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
    /// The word row and the pile are eight tiles wide — fewer, bigger tiles
    /// than the original ten, which is what makes them thumb-sized on a phone.
    static let columns = 8
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

    /// How wide a tile is when `columns` of them fill `width`.
    static func tileSize(fitting width: CGFloat) -> CGFloat {
        max(20, (width - CGFloat(columns - 1) * tileGap) / CGFloat(columns))
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
