import SwiftUI
import WordBoard
import WordCore

/// The pile (Rack.tsx): tiles in rows capped at ten wide, the field centered
/// while its rows fill from the left, the shuffle button pinned to the corner
/// rather than scrolling with the tiles. Picked tiles lift, invert, and wear
/// a 1-based order badge (styles.css:572–586).
struct RackView: View {
    var letters: [String]
    var hiddenIndex: Int?
    /// Rack indices claimed by the word being built, in typed order.
    var picks: [Int]
    /// Feeds the unified gesture layer — one pipeline for every pointer.
    var pointerEvent: (GestureMachine.Event) -> Void
    var downTarget: (Int, String) -> GestureMachine.DownTarget
    var onShuffle: () -> Void

    private static let tileSize: Double = 44
    private static let spacing: Double = 8

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if letters.isEmpty {
                    Text("Pile empty — every tile is on the board")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(
                            minimum: Self.tileSize, maximum: Self.tileSize),
                            spacing: Self.spacing)],
                        spacing: Self.spacing
                    ) {
                        ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                            RackTileView(
                                letter: letter,
                                pickOrder: picks.firstIndex(of: index).map { $0 + 1 }
                            )
                            .opacity(index == hiddenIndex ? 0 : 1)
                            .pointerSurface(
                                target: { _ in downTarget(index, letter) },
                                dispatch: pointerEvent)
                        }
                    }
                    // Ten tiles a row, like the web's capped rack field.
                    .frame(maxWidth: (Self.tileSize + Self.spacing) * 10)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // Keep tiles clear of the pinned shuffle button (styles.css:1355).
            .padding(.trailing, 50)
            .padding(.leading, 18)

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
            .padding(8)
        }
        .background(Ink.surfaceAlt)
    }
}

struct RackTileView: View {
    var letter: String
    var pickOrder: Int?

    var body: some View {
        let picked = pickOrder != nil
        RoundedRectangle(cornerRadius: 8)
            .fill(picked ? Ink.ink : Ink.tileFace)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(picked ? Ink.ink : Ink.tileEdge, lineWidth: 2)
            )
            .overlay(
                Text(letter.uppercased())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(picked ? Ink.inkInvert : Ink.ink)
            )
            .overlay(alignment: .topTrailing) {
                if let pickOrder {
                    Text("\(pickOrder)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Ink.inkInvert))
                        .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.5))
                        .offset(x: 5, y: -5)
                }
            }
            .shadow(color: .black.opacity(picked ? 0 : 0.18), radius: 0, x: 0, y: 2)
            .frame(width: 44, height: 44)
            .offset(y: picked ? -4 : 0)
    }
}

/// A tile riding under the pointer (z above everything, App.tsx:3347–3357).
struct GhostTileView: View {
    var letter: String

    var body: some View {
        RackTileView(letter: letter, pickOrder: nil)
            .scaleEffect(1.08)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .allowsHitTesting(false)
    }
}
