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

// MARK: - QuestArt: real asset if present, else PlaceholderArt (drop-in, per-key)
//
//  The single art seam. Every art slot renders a QuestArt with a LOGICAL key
//  (see QuestArtKey) and the locked ratio; if the named image exists in the asset
//  catalog it's shown (filled + clipped to the same rounded card, solid black
//  border), otherwise it degrades to the dashed PlaceholderArt with the same
//  ratio/colors/symbol/caption. Sizing matches PlaceholderArt exactly (aspectRatio
//  fit on a clear anchor), so a present asset and a missing one occupy the same
//  footprint — art lights up one-by-one with ZERO layout changes as it's drawn.
//
//  Asset naming = the key string verbatim (see QuestArtKey): "pet-barrelback",
//  "portrait-forest-elf", "emblem-shield". Name catalog entries to match and they
//  appear; anything unnamed stays a placeholder.

struct QuestArt: View {
    let name: String            // asset-catalog name == the logical key
    let ratio: CGFloat
    // Fallback styling (used only on a catalog miss — matches PlaceholderArt).
    var colors: [Color] = [Color(hex: "C9B6DA"), Color(hex: "A8CBE4")]
    var symbol: String = "sparkles"
    var caption: String? = nil
    /// framed (default): fill + clip to a rounded card with a black border — for
    /// portraits and any art drawn to fill a frame. Unframed: a present image sits
    /// BORDERLESS and UNCROPPED (scaledToFit, transparent background preserved) — for
    /// art drawn to float on the page, like the pet illustrations. Either way a
    /// MISSING asset still falls back to the dashed placeholder.
    var framed: Bool = true

    var body: some View {
        if let ui = UIImage(named: name) {
            if framed {
                Color.clear
                    .aspectRatio(ratio, contentMode: .fit)
                    .overlay { Image(uiImage: ui).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
            } else {
                // Sits on the page: whole image, no crop, no border, alpha intact.
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            PlaceholderArt(ratio: ratio, colors: colors, symbol: symbol, caption: caption)
        }
    }
}

/// True if a named asset exists in the catalog. Pickers use this to show only drawn
/// art, so undrawn slots never render as empty cells.
func questAssetExists(_ name: String) -> Bool { UIImage(named: name) != nil }

// MARK: - QuestArtKey: the logical key scheme (asset-catalog names)
//
//  One place that turns content IDs into catalog names, so views never hardcode
//  art names. Keys are the asset names verbatim — name your Assets.xcassets entries
//  to match. `portrait(_:)` is the sheet portrait's auto-by-race default; a kid's
//  gallery pick (stored on the character) overrides it when that lands.

enum QuestArtKey {
    /// Prefixes a pet art slug: a gallery slot ("3" -> pet-3), or a book companion id
    /// ("barrelback" -> pet-barrelback, optional bespoke art) — all "pet-<x>".
    static func pet(_ slug: String) -> String { "pet-\(slug)" }
    static let customPet = "pet-custom"          // custom (companion-less) pets
    /// Generic pet-image pool the picker probes (pet-1 … pet-N). This is just a CEILING
    /// with headroom — the picker shows only slots whose asset actually exists, so
    /// unused numbers (and numbering gaps) never appear. Raise it only when you pass N.
    /// Stored on PetChoice.imageID as the bare slot ("3").
    static let petArtSlotCount = 120
    /// Prefixes a spirit-animal art slot ("2" -> spirit-2). The Druid's spirit uses a
    /// generic pool like pets; the pick persists on CharacterChoices.spiritImageID.
    static func spirit(_ slug: String) -> String { "spirit-\(slug)" }
    /// Generic spirit-image pool the picker probes (spirit-1 … spirit-N). Ceiling with
    /// headroom — only existing slots show. Stored on CharacterChoices.spiritImageID.
    static let spiritArtSlotCount = 60

    /// Race×class portrait combo. `combo` is portraitCombo(race:klass:) — an opaque
    /// "<raceID>-<classID>" string (never parsed back). Kids can pick ANY combo's art
    /// as their look; the gallery derives every race×class cell, so new portrait
    /// assets light up their cell with zero code changes.
    static func portrait(combo: String) -> String { "portrait-\(combo)" }
    static func portraitCombo(race: String, klass: String) -> String { "\(race)-\(klass)" }
    /// Variations per race×class portrait combo. The base image (unsuffixed) is
    /// variant 1; extras are "-2" … "-N" (portrait-lizardfolk-healer-2, etc.). The
    /// gallery probes base + -2…N and shows every one that exists. Ceiling with
    /// headroom — raise only if a combo needs more than this many looks.
    static let portraitVariantSlots = 12
    /// Generic portraits NOT tied to a race×class — the gallery's "Something Different"
    /// section. Combo key is "any-N" (asset portrait-any-N); the picker probes 1…N and
    /// shows only those that exist. "any" can't collide with a "<race>-<class>" combo.
    static func portraitMisc(_ slug: String) -> String { "any-\(slug)" }
    static let portraitMiscSlots = 40
    static func race(_ id: String) -> String { "race-\(id)" }   // creation race cards / lineup
    static func klass(_ id: String) -> String { "class-\(id)" }
    static func path(_ id: String) -> String { "path-\(id)" }
    static func emblem(_ id: String) -> String { "emblem-\(id)" }
    static func weapon(_ id: String) -> String { "weapon-\(id)" }
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
