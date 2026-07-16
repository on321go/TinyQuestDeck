//  HeroTile.swift
//  Identity, themed from the character's ThemeToken (class theme, or path
//  themeOverride). The circular portrait slot now shows the character's CHOSEN
//  portrait (character.portraitID, or their race×class default) cropped into the
//  circle; it falls back to the initial badge when that art hasn't been drawn yet.

import SwiftUI

// MARK: - Theme plumbing

extension Color {
    /// Accepts "#RRGGBB" or "#RRGGBBAA" (the form used in content.json themes).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: UInt64
        switch s.count {
        case 8: (r, g, b, a) = (v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
        case 6: (r, g, b, a) = (v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF, 255)
        default: (r, g, b, a) = (128, 128, 128, 255)
        }
        self = Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                     blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

/// Maps a ThemeToken.emblem motif to an SF Symbol (stand-in until real emblem art).
func emblemSymbol(_ emblem: String?) -> String {
    switch emblem {
    case "shield":        return "shield.fill"
    case "spellbook-orb": return "wand.and.stars"
    case "tarot":         return "moon.stars.fill"
    case "bow":           return "target"
    default:              return "sparkle"
    }
}

func heroTheme(_ c: CharacterChoices, repo: ContentRepository) -> ThemeToken? {
    guard let cls = repo.klass(c.classID) else { return nil }
    return repo.path(c.pathID)?.themeOverride ?? cls.theme
}

// Grid context-menu delete helper.
//extension RosterStore {
//    func remove(_ c: CharacterChoices) { characters.removeAll { $0.id == c.id } }
//}

// MARK: - Tile

struct HeroTile: View {
    let character: CharacterChoices
    let repo: ContentRepository

    var body: some View {
        let theme  = heroTheme(character, repo: repo)
        let bg     = theme.map { Color(hex: $0.background) } ?? .gray
        let panel  = theme.map { Color(hex: $0.panel) }      ?? .white
        let accent = theme.map { Color(hex: $0.accent) }     ?? .blue
        let ink    = theme.map { Color(hex: $0.ink) }        ?? .primary

        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [bg, bg.opacity(0.72)],
                                 startPoint: .top, endPoint: .bottom))
            // emblem watermark
            .overlay(alignment: .topTrailing) {
                Image(systemName: emblemSymbol(theme?.emblem))
                    .font(.system(size: 84))
                    .foregroundStyle(ink.opacity(0.12))
                    .offset(x: 16, y: -6)
            }
            // portrait slot — chosen portrait cropped to the circle, else the initial
            .overlay(alignment: .topLeading) {
                ZStack {
                    Circle().fill(panel)
                    if let ui = UIImage(named: portraitName) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Text(initial).font(.title2.weight(.bold)).foregroundStyle(ink)
                    }
                    Circle().strokeBorder(accent, lineWidth: 2)   // ring on top, frames the art
                }
                .frame(width: 52, height: 52)
                .padding(14)
            }
            // name + class/path
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(character.name).font(.headline).foregroundStyle(ink).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(ink.opacity(0.7)).lineLimit(1)
                }
                .padding(14)
            }
            .frame(height: 158)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }

    /// The chosen portrait (or the race×class default) as an asset name — same
    /// resolution the character sheet uses, so tile and sheet stay in sync.
    private var portraitName: String {
        let combo = character.portraitID
            ?? QuestArtKey.portraitCombo(race: character.raceID, klass: character.classID)
        return QuestArtKey.portrait(combo: combo)
    }

    private var initial: String {
        String(character.name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased()
    }
    private var subtitle: String {
        let cls = repo.klass(character.classID)?.name ?? ""
        let path = repo.path(character.pathID)?.name ?? ""
        return path.isEmpty ? cls : "\(cls) · \(path)"
    }
}

// MARK: - Collection grid

struct HeroGrid: View {
    let characters: [CharacterChoices]
    let repo: ContentRepository
    var onDelete: (CharacterChoices) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(characters) { c in
                    NavigationLink(value: c) {
                        HeroTile(character: c, repo: repo)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { onDelete(c) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }
}
