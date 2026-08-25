import SwiftUI
import WordBoard
import WordCore

/// The pile (Rack.tsx): tiles in rows capped at ten wide, the field centered
/// while its rows fill from the left, the shuffle button pinned to the top
/// corner rather than scrolling with the tiles. Picked tiles lift, invert, and
/// wear a 1-based order badge (styles.css:572–586).
struct RackView: View {
    var letters: [String]
    var hiddenIndex: Int?
    /// Rack indices claimed by the word being built, in typed order.
    var picks: [Int]
    /// Feeds the unified gesture layer — one pipeline for every pointer.
    var pointerEvent: (GestureMachine.Event) -> Void
    var downTarget: (Int, String) -> GestureMachine.DownTarget
    var onShuffle: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The web's rack geometry (styles.css:1370–1383): a tile is `--cell` less
    /// its 4px of border, the gap is 6, and below 600px the cell itself drops
    /// from 44 to 38 (styles.css:1740). That last step is what fits eight tiles
    /// in a phone's row rather than six — the row is the unit a player scans,
    /// so the port keeps the count rather than the point size.
    static func tileSize(for sizeClass: UserInterfaceSizeClass?) -> Double {
        sizeClass == .compact ? 34 : 40
    }

    private static let spacing: Double = 6
    private static let columnCap = 10

    private var tileSize: Double { Self.tileSize(for: sizeClass) }
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if letters.isEmpty {
                    Text("Pile empty — every tile is on the board")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    // The pile scrolls past a few rows rather than growing
                    // without limit (the web caps it at 28vh, styles.css:1360).
                    // The ScrollView is load-bearing for layout, not just
                    // overflow: a bare LazyVGrid asked for its ideal size
                    // stacks every tile into one column — a thousand points of
                    // demanded height, which becomes the window's minimum and
                    // pushes the pile off the screen.
                    ScrollView(.vertical) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(
                                minimum: tileSize, maximum: tileSize),
                                spacing: Self.spacing)],
                            spacing: Self.spacing
                        ) {
                        ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                            let pickOrder = picks.firstIndex(of: index).map { $0 + 1 }
                            RackTileView(letter: letter, pickOrder: pickOrder, size: tileSize)
                                .opacity(index == hiddenIndex ? 0 : 1)
                                .pointerSurface(
                                    target: { _ in downTarget(index, letter) },
                                    dispatch: pointerEvent)
                                // Rack tiles are bare divs on the web too
                                // (Rack.tsx:40–56); the port names them.
                                .accessibilityElement()
                                .accessibilityLabel(
                                    pickOrder.map {
                                        "\(letter.uppercased()), tile \(index + 1) of "
                                            + "\(letters.count), letter \($0) of your word"
                                    } ?? "\(letter.uppercased()), tile \(index + 1) of \(letters.count)")
                                .accessibilityHint(
                                    pickOrder == nil
                                        ? "Adds this letter to your word"
                                        : "Takes this letter back out of your word")
                                .accessibilityAddTraits(
                                    pickOrder == nil ? .isButton : [.isButton, .isSelected])
                        }
                        }
                        // Ten tiles a row, like the web's capped rack field.
                        .frame(maxWidth: tileSize * Double(Self.columnCap)
                            + Self.spacing * Double(Self.columnCap - 1))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    // Room for three rows before it scrolls; one row's worth
                    // is the floor so the pile never collapses to nothing.
                    .frame(
                        minHeight: tileSize + Self.spacing,
                        maxHeight: (tileSize + Self.spacing) * 3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // Clearance for the pinned shuffle button, with a phone tightening
            // the left margin to buy row width (styles.css:1355, 1798–1802).
            // The web drops the clearance past 600px, where a capped field can
            // no longer reach the button; a Mac window can be narrower than
            // that and still be a regular size class, so the port keeps it.
            .padding(.trailing, compact ? 50 : 56)
            .padding(.leading, compact ? 12 : 18)

            Button(action: onShuffle) {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Ink.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Shuffle the pile")
            // The pile's top corner, where the web pins it (styles.css:1391).
            .padding(.top, 8)
            .padding(.trailing, 12)
        }
        .background(Ink.surfaceAlt)
    }
}

struct RackTileView: View {
    var letter: String
    var pickOrder: Int?
    var size: Double

    var body: some View {
        let picked = pickOrder != nil
        // The badge holds its proportion to the tile. The letter doesn't: the
        // web's is a flat 21px whatever the tile measures (styles.css:515), so
        // a phone's smaller tile carries a proportionally bigger letter.
        let badge = size * 0.36
        RoundedRectangle(cornerRadius: 8)
            .fill(picked ? Ink.ink : Ink.tileFace)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(picked ? Ink.ink : Ink.tileEdge, lineWidth: 2)
            )
            .overlay(
                Text(letter.uppercased())
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(picked ? Ink.inkInvert : Ink.ink)
            )
            .overlay(alignment: .topTrailing) {
                if let pickOrder {
                    Text("\(pickOrder)")
                        .font(.system(size: badge * 0.7, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .frame(width: badge, height: badge)
                        .background(Circle().fill(Ink.inkInvert))
                        .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.5))
                        .offset(x: badge * 0.3, y: -badge * 0.3)
                }
            }
            .shadow(color: .black.opacity(picked ? 0 : 0.18), radius: 0, x: 0, y: 2)
            .frame(width: size, height: size)
            .offset(y: picked ? -4 : 0)
    }
}

/// A tile riding under the pointer (z above everything, App.tsx:3347–3357).
struct GhostTileView: View {
    var letter: String
    /// Matches the pile it came out of, so the tile doesn't change size on lift.
    var size: Double

    var body: some View {
        RackTileView(letter: letter, pickOrder: nil, size: size)
            .scaleEffect(1.08)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .allowsHitTesting(false)
    }
}
