//  Rulebook.swift
//  Content-is-data for the in-app rulebook, mirroring content.json → repository.
//  The rulebook holds ONLY the "how to play" prose the app doesn't already render —
//  it deliberately does NOT duplicate stats, class/path/kind/spell/gear data, which
//  live in content.json and are the single source of truth (the live app screens ARE
//  that reference). Concept tables (stat meanings, weapon CATEGORIES) are included
//  because they teach ideas; specific item lists are not, to avoid two copies drifting.
//
//  Block is a tagged enum like EffectHint — extensible (a future .crossLink into an
//  ability/spell is just another case). Decoding tolerates unknown kinds via .unknown
//  so an older build never crashes on newer content.

import Foundation

// MARK: - Models

struct Rulebook: Codable {
    let sections: [RuleSection]
}

/// group: "player" or "gm" — drives the two-group section list.
struct RuleSection: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let group: RuleGroup
    let icon: String            // SF Symbol for the section chip
    let blocks: [RuleBlock]

    /// Plain text of every block, lowercased — the search haystack.
    var searchText: String {
        (title + " " + blocks.map(\.plainText).joined(separator: " ")).lowercased()
    }
}

enum RuleGroup: String, Codable, Hashable {
    case player, gm
    var label: String { self == .player ? "Playing the Game" : "For the Game Master" }
}

/// A content block. Tagged by `kind` in JSON. Callouts carry a tier for coloring
/// (starting/path/signature → green/purple/orange), reusing TierColor.
enum RuleBlock: Codable, Hashable {
    case heading(String)                                   // subsection heading within a section
    case paragraph(String)
    case bullets([String])
    case callout(title: String, body: [String], tier: CalloutTier)
    case table(headers: [String], rows: [[String]])
    case image(key: String)                                // QuestArt, keyed rules-<key>
    case unknown

    /// Text used for search (callouts/tables flattened).
    var plainText: String {
        switch self {
        case .heading(let t):            return t
        case .paragraph(let t):          return t
        case .bullets(let xs):           return xs.joined(separator: " ")
        case .callout(let title, let body, _): return title + " " + body.joined(separator: " ")
        case .table(let h, let rows):    return (h + rows.flatMap { $0 }).joined(separator: " ")
        case .image, .unknown:           return ""
        }
    }

    // Tagged Codable
    private enum CodingKeys: String, CodingKey {
        case kind, text, items, title, body, tier, headers, rows, key
    }
    private enum Kind: String, Codable {
        case heading, paragraph, bullets, callout, table, image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let kind = try? c.decode(Kind.self, forKey: .kind) else { self = .unknown; return }
        switch kind {
        case .heading:   self = .heading(try c.decode(String.self, forKey: .text))
        case .paragraph: self = .paragraph(try c.decode(String.self, forKey: .text))
        case .bullets:   self = .bullets(try c.decode([String].self, forKey: .items))
        case .callout:
            self = .callout(title: try c.decode(String.self, forKey: .title),
                            body: try c.decode([String].self, forKey: .body),
                            tier: (try? c.decode(CalloutTier.self, forKey: .tier)) ?? .starting)
        case .table:
            self = .table(headers: try c.decode([String].self, forKey: .headers),
                          rows: try c.decode([[String]].self, forKey: .rows))
        case .image:     self = .image(key: try c.decode(String.self, forKey: .key))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let t):   try c.encode(Kind.heading, forKey: .kind);   try c.encode(t, forKey: .text)
        case .paragraph(let t): try c.encode(Kind.paragraph, forKey: .kind); try c.encode(t, forKey: .text)
        case .bullets(let xs):  try c.encode(Kind.bullets, forKey: .kind);   try c.encode(xs, forKey: .items)
        case let .callout(title, body, tier):
            try c.encode(Kind.callout, forKey: .kind)
            try c.encode(title, forKey: .title); try c.encode(body, forKey: .body); try c.encode(tier, forKey: .tier)
        case let .table(headers, rows):
            try c.encode(Kind.table, forKey: .kind)
            try c.encode(headers, forKey: .headers); try c.encode(rows, forKey: .rows)
        case .image(let key):   try c.encode(Kind.image, forKey: .kind); try c.encode(key, forKey: .key)
        case .unknown:          break
        }
    }
}

/// Callout accent, mapped to the app's tier colors in the view.
enum CalloutTier: String, Codable, Hashable {
    case starting   // green  — examples / core facts
    case path       // purple — tips / GM notes
    case signature  // orange — big-deal / warnings ("Legendary", "Remember!")
}

// MARK: - Store (mirrors ContentStore)

@MainActor
@Observable
final class RulebookStore {
    var rulebook: Rulebook?
    var error: String?

    var playerSections: [RuleSection] { rulebook?.sections.filter { $0.group == .player } ?? [] }
    var gmSections: [RuleSection] { rulebook?.sections.filter { $0.group == .gm } ?? [] }

    /// Case-insensitive keyword match across titles + block text.
    func sections(matching query: String) -> [RuleSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return rulebook?.sections ?? [] }
        return (rulebook?.sections ?? []).filter { $0.searchText.contains(q) }
    }

    func load() {
        guard let url = Bundle.main.url(forResource: "rulebook", withExtension: "json") else {
            error = "rulebook.json not found in bundle."
            return
        }
        do {
            rulebook = try JSONDecoder().decode(Rulebook.self, from: Data(contentsOf: url))
        } catch {
            self.error = "Failed to parse rulebook.json: \(error)"
        }
    }
}
