//  QuestStyle.swift
//  Shared visual vocabulary for the new UI: the marker font, the black-outline card
//  look, the semantic tier colors (green = starting, purple = path, orange = signature),
//  chips, cream panels, and gradient placeholder art at the locked aspect ratios.
//
//  Depends on Color(hex:) and emblemSymbol(_:) from HeroTile.swift.
//
//  ASPECT RATIOS (locked — real art drops in with zero layout changes):
//    QuestRatio.card    5:7   race cards, detail-card, character portraits (1200×1680)
//    QuestRatio.tall    9:16  path/class combo tiles + path detail portrait (1080×1920)
//    QuestRatio.banner  3:2   group lineup banners (2048×1365)
//    QuestRatio.portal  3:4   the New Hero portal illustration (1536×2048)

import SwiftUI

// MARK: - Ratios

enum QuestRatio {
    static let card: CGFloat   = 5.0 / 7.0
    static let tall: CGFloat   = 9.0 / 16.0
    static let banner: CGFloat = 3.0 / 2.0
    static let portal: CGFloat = 3.0 / 4.0
}

// MARK: - Semantic tier colors (global: detail screens, sheet abilities, spellbook)

enum TierColor {
    static let starting  = Color(hex: "17A34A")   // green  — core kit / class abilities
    static let path      = Color(hex: "7B2FBE")   // purple — Path Powers (L2)
    static let signature = Color(hex: "F0821E")   // orange — Signature Powers (L3)

    static let panelCream = Color(hex: "FBF6D8")  // the cream fields from the mockups
    static let selectPeach = Color(hex: "F9CBB0") // the SELECT button fill
}

// MARK: - The marker font (Chalkboard SE ships with iOS and matches the mockup hand)

func questFont(_ size: CGFloat) -> Font { .custom("ChalkboardSE-Bold", size: size) }
func questFontLight(_ size: CGFloat) -> Font { .custom("ChalkboardSE-Regular", size: size) }

// MARK: - Chip (the "NAME GOES HERE" / "PICK A CLASS" lozenges)

struct QuestChip: View {
    let text: String
    var fill: Color = Color(hex: "A8CBE4")
    var size: CGFloat = 20

    var body: some View {
        Text(text.uppercased())
            .font(questFont(size))
            .foregroundStyle(.black)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Select button (peach, top-right of detail screens)

struct SelectButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("SELECT")
                .font(questFont(22))
                .foregroundStyle(.black)
                .padding(.horizontal, 34).padding(.vertical, 10)
                .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cream panel with a tier-colored title (Build Info / Starting Kit / Path Power / Signature)

struct TierPanel<Content: View>: View {
    let title: String
    var titleColor: Color = .black
    var icon: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).font(questFont(20)).foregroundStyle(titleColor)
                if let icon { Image(systemName: icon).font(.headline).foregroundStyle(titleColor) }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Gradient placeholder art (dashed border marks it as a stand-in)

struct PlaceholderArt: View {
    let ratio: CGFloat
    var colors: [Color] = [Color(hex: "C9B6DA"), Color(hex: "A8CBE4")]
    var symbol: String = "sparkles"
    var caption: String? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.85))
                    if let caption {
                        Text(caption).font(questFontLight(13)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.black, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            )
    }
}

// MARK: - Per-race tile tints (the pastel card backdrops in the Pick-a-Kind grid)

func raceTint(_ raceID: String) -> Color {
    switch raceID {
    case "sprite":      Color(hex: "C9C4EC")
    case "foxfolk":     Color(hex: "D6C6B5")
    case "catfolk":     Color(hex: "F4C9CE")
    case "lizardfolk":  Color(hex: "BFE5DD")
    case "cloudkin":    Color(hex: "A9D3EC")
    case "human":       Color(hex: "F6EEDD")
    case "stoneling":   Color(hex: "D8D3C8")
    case "forest-elf":  Color(hex: "CDE3BE")
    default:            Color(hex: "E3DFEF")
    }
}

// MARK: - Small display helper: "(Reaction) · Recharge" line under ability names

func usageLine(_ a: AbilityDefinition) -> String {
    "(\(a.actionCost.rawValue.capitalized)) · \(a.reset.rawValue)"
}
