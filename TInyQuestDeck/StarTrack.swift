//  StarTrack.swift
//  The hero's progression track: six star slots, threshold flags at 3 (Level 2) and
//  6 (Level 3). Lives in the sheet's header control cluster next to the gold display
//  and the Hero Card (QR) button — gold, Hero Card, stars: the hero's ledger in one
//  row, all three fed by the GM award pipeline.
//
//  The track never levels anybody. It shows what's banked; `hero.canLevelUp` lights
//  the level badge, and the existing point-spend flow is still the only thing that
//  changes a hero's build.
//
//  Visual language matches the HP/showcase boxes: cream field, black outline, marker
//  font, signature orange for a filled star (the same orange as Signature Powers —
//  stars ARE the big-deal currency). On paper these are literally stickers.
//
//  Depends on QuestStyle.swift (TierColor, questFont) and CharacterChoices.

import SwiftUI

struct StarTrack: View {
    let stars: Int
    /// Draws attention when the stars are banked but unspent. The level badge is the
    /// real call to action; this just stops the track looking inert at the moment it
    /// matters most.
    var readyToLevel: Bool = false

    /// DEV / honor-system controls. Non-nil shows the buttons. These are the ONLY way
    /// a star reaches a kid's iPad until QR Milestone B ships and is proven on two
    /// devices — they retire alongside the sheet's dev gold stepper, not before.
    var onAdd: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    private var slots: Int { CharacterChoices.starTrackLength }
    private var filled: Int { min(max(0, stars), slots) }
    private var overflow: Int { max(0, stars - slots) }

    /// Slot indices a threshold lands ON (0-based): 3 stars → index 2, 6 → index 5.
    private var flagIndices: Set<Int> {
        Set(CharacterChoices.starThresholds.map { $0 - 1 })
    }

    var body: some View {
        HStack(spacing: 6) {
            if let onRemove {
                stepButton("minus", action: onRemove)
                    .disabled(stars <= 0)
                    .opacity(stars <= 0 ? 0.35 : 1)
            }

            HStack(spacing: 4) {
                ForEach(0 ..< slots, id: \.self) { i in
                    slot(i)
                    // The Level 2 flag: a checkpoint between the 3rd and 4th slot.
                    // (The last threshold sits at the end of the track, so no divider.)
                    if flagIndices.contains(i), i < slots - 1 {
                        Rectangle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 2, height: 18)
                            .padding(.horizontal, 1)
                    }
                }

                if overflow > 0 {
                    // Banked past the last threshold — kept, not shown as slots, until
                    // levels 4+ exist to spend them on.
                    Text("+\(overflow)")
                        .font(questFont(13))
                        .foregroundStyle(.black.opacity(0.5))
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(TierColor.panelCream, in: Capsule())
            .overlay(
                Capsule().strokeBorder(readyToLevel ? TierColor.signature : .black,
                                       lineWidth: readyToLevel ? 3 : 2)
            )

            if let onAdd {
                stepButton("plus", action: onAdd)
            }
        }
        .animation(.snappy(duration: 0.2), value: stars)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Star track")
        .accessibilityValue("\(stars) of \(slots) stars\(readyToLevel ? ", ready to level up" : "")")
    }

    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        Image(systemName: i < filled ? "star.fill" : "star")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(i < filled ? TierColor.signature : .black.opacity(0.25))
            .scaleEffect(i < filled ? 1 : 0.9)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(TierColor.panelCream, in: Circle())
                .overlay(Circle().strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        StarTrack(stars: 0)
        StarTrack(stars: 2)
        StarTrack(stars: 3, readyToLevel: true)
        StarTrack(stars: 6, readyToLevel: true, onAdd: {}, onRemove: {})
        StarTrack(stars: 8, onAdd: {}, onRemove: {})
    }
    .padding(24)
    .background(Color(hex: "CDE3BE"))
}
