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

// MARK: - Sub-models for the richer block kinds

/// One beat of a numbered spine (`steps`). `icon` REPLACES the number in the bubble
/// (the Big Idea's final "Go play" checkmark). `highlight` renders a single emphasized
/// pill under the body — reserved for the one sentence that matters most on the page
/// (THE ONE RULE). `blocks` nests further blocks INSIDE the step, indented on the
/// spine: the class-picker card grid (step 1) and the action-economy block (step 4).
/// Nesting is intended one level deep; deeper works but nothing needs it.
struct RuleStep: Codable, Hashable {
    let n: Int
    let title: String
    let body: String?
    let icon: String?
    let highlight: String?
    let highlightIcon: String?
    let blocks: [RuleBlock]?

    var plainText: String {
        [title, body, highlight].compactMap { $0 }.joined(separator: " ")
        + " " + (blocks?.map(\.plainText).joined(separator: " ") ?? "")
    }
}

/// A mini-card in a `cards` grid. One view, three uses: the class picker (plain), the
/// GM four-up (plain), and the action-economy block (colored + badged).
/// `badge` is the cost badge — the teaching device on the economy block.
struct RuleCard: Codable, Hashable {
    let title: String
    let text: String?
    let examples: String?
    let icon: String?
    let badge: String?
    let color: EconomyColor?

    var plainText: String {
        [title, text, examples, badge].compactMap { $0 }.joined(separator: " ")
    }
}

/// One line of the sample-turn strip. `joined` draws a "+" between chips (a turn adds
/// up); a row with a `label` and no join renders the "not your turn" line, whose
/// spatial separation IS the lesson.
struct RuleChipRow: Codable, Hashable {
    let label: String?
    let joined: Bool?
    let items: [RuleChip]

    var plainText: String {
        ((label.map { [$0] } ?? []) + items.map(\.text)).joined(separator: " ")
    }
}

struct RuleChip: Codable, Hashable {
    let text: String
    let color: EconomyColor?
}

/// The action-economy color language (RULEBOOK_ONBOARDING_AND_XP_SPEC §2.1).
/// Move = blue, your one thing = coral, Free Action = green, Reaction = purple.
/// Scope is deliberately page-local: it's a quick visual aid inside the Big Idea's
/// economy block, NOT a global contract — the overlap with the reader's player-green /
/// GM-purple page tints is known and accepted. Unknown values decode to `.plain`,
/// matching RuleBlock.unknown's forward-compat stance.
enum EconomyColor: String, Codable, Hashable {
    case move, thing, free, reaction, plain

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EconomyColor(rawValue: raw) ?? .plain
    }
}

// MARK: - Block

/// A content block. Tagged by `kind` in JSON. Callouts carry a tier for coloring
/// (starting/path/signature → green/purple/orange), reusing TierColor.
enum RuleBlock: Codable, Hashable {
    case heading(String)                                   // subsection heading within a section
    case paragraph(String)
    case bullets([String])
    case callout(title: String, body: [String], tier: CalloutTier)
    case table(headers: [String], rows: [[String]])
    case image(key: String)                                // QuestArt, keyed rules-<key>
    case steps([RuleStep])                                 // numbered spine (Big Idea, GM loop)
    case cards(columns: Int, items: [RuleCard])            // mini-card grid
    case chips(title: String?, rows: [RuleChipRow])        // sample-turn strip
    case crossLink(title: String?, targets: [String])      // pill row → other sections
    case unknown

    /// Text used for search (callouts/tables/steps/cards flattened). crossLink is
    /// pointer-only — its labels come from the sections it links, which are already
    /// in the haystack under their own ids, so it contributes nothing.
    var plainText: String {
        switch self {
        case .heading(let t):            return t
        case .paragraph(let t):          return t
        case .bullets(let xs):           return xs.joined(separator: " ")
        case .callout(let title, let body, _): return title + " " + body.joined(separator: " ")
        case .table(let h, let rows):    return (h + rows.flatMap { $0 }).joined(separator: " ")
        case .steps(let items):          return items.map(\.plainText).joined(separator: " ")
        case .cards(_, let items):       return items.map(\.plainText).joined(separator: " ")
        case .chips(let title, let rows):
            return ((title.map { [$0] } ?? []) + rows.map(\.plainText)).joined(separator: " ")
        case .image, .crossLink, .unknown: return ""
        }
    }

    // Tagged Codable
    private enum CodingKeys: String, CodingKey {
        case kind, text, items, title, body, tier, headers, rows, key, columns, targets
    }
    private enum Kind: String, Codable {
        case heading, paragraph, bullets, callout, table, image, steps, cards, chips, crossLink
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
        case .steps:     self = .steps(try c.decode([RuleStep].self, forKey: .items))
        case .cards:
            self = .cards(columns: (try? c.decode(Int.self, forKey: .columns)) ?? 2,
                          items: try c.decode([RuleCard].self, forKey: .items))
        case .chips:
            self = .chips(title: try? c.decode(String.self, forKey: .title),
                          rows: try c.decode([RuleChipRow].self, forKey: .rows))
        case .crossLink:
            self = .crossLink(title: try? c.decode(String.self, forKey: .title),
                              targets: try c.decode([String].self, forKey: .targets))
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
        case .steps(let items): try c.encode(Kind.steps, forKey: .kind);  try c.encode(items, forKey: .items)
        case let .cards(columns, items):
            try c.encode(Kind.cards, forKey: .kind)
            try c.encode(columns, forKey: .columns); try c.encode(items, forKey: .items)
        case let .chips(title, rows):
            try c.encode(Kind.chips, forKey: .kind)
            try c.encodeIfPresent(title, forKey: .title); try c.encode(rows, forKey: .rows)
        case let .crossLink(title, targets):
            try c.encode(Kind.crossLink, forKey: .kind)
            try c.encodeIfPresent(title, forKey: .title); try c.encode(targets, forKey: .targets)
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

    /// Resolve a section id — the seam `crossLink` pills use to render their labels
    /// from the live section titles instead of duplicating them into the JSON.
    /// A bad/renamed id returns nil and the pill is simply dropped.
    func section(_ id: String) -> RuleSection? {
        rulebook?.sections.first { $0.id == id }
    }

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
