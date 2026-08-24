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

/// One book's on-disk payload — `<id>.json` (rulebook.json, almanac.json, …).
/// Deliberately the SAME `{ "sections": [...] }` shape the rulebook has always used,
/// so rulebook.json is untouched by the move to a multi-book library.
struct BookFile: Codable {
    let sections: [RuleSection]
}

/// library.json — the table of contents. Metadata ONLY; a book's rules text lives in
/// its own `<id>.json`. Adding a book = one entry here + one file, no code.
struct BookCatalog: Codable {
    let books: [BookInfo]
}

/// A catalog entry. `id` doubles as the sections-file stem ("rulebook" → rulebook.json).
struct BookInfo: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let blurb: String            // one-line description on the cover card
    let coverArt: String         // QuestArt asset key, e.g. "book-cover-rulebook"
    let coverSymbol: String      // SF Symbol fallback until the cover art is drawn
    let deckBrowser: Bool?        // opt-in Browse Classes/Kinds row (rulebook today). nil = off.
}

/// A catalog entry joined to its loaded sections — what the reader renders and what
/// NavigationLinks carry. Assembled at load time, so not Codable.
struct Book: Identifiable, Hashable {
    let info: BookInfo
    let sections: [RuleSection]

    var id: String { info.id }
    var title: String { info.title }
    var showsDeckBrowser: Bool { info.deckBrowser ?? false }

    /// The two group buckets, unchanged from the old store-level split.
    var playerSections: [RuleSection] { sections.filter { $0.group == .player } }
    var gmSections: [RuleSection] { sections.filter { $0.group == .gm } }

    /// Case-insensitive keyword match across this book's titles + block text.
    func sections(matching query: String) -> [RuleSection] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sections }
        return sections.filter { $0.searchText.contains(q) }
    }
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

/// One fighter chip inside a place — display-only strings, no game logic.
/// `hp` is whatever the page wants to show ("9/9"); the rulebook never computes.
struct PlaceFighter: Codable, Hashable {
    let name: String
    let hp: String
    let side: FighterSide

    var initial: String { String(name.prefix(1)).uppercased() }
    var plainText: String { name }
}

/// hero = blue chip, monster = red chip. Tolerant decode like EconomyColor —
/// an unknown side renders as a monster rather than failing the whole block.
enum FighterSide: String, Codable, Hashable {
    case hero, monster

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FighterSide(rawValue: raw) ?? .monster
    }
}

/// One place card in a `places` diagram. `lock` doubles as the locked flag —
/// its presence draws the dashed gold border and the lock pill; no separate bool.
struct PlaceSpot: Codable, Hashable {
    let name: String
    let lock: String?               // "Speed 12 to climb" — nil = open place
    let fighters: [PlaceFighter]

    var plainText: String {
        ([name] + (lock.map { [$0] } ?? []) + fighters.map(\.plainText)).joined(separator: " ")
    }
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
    case places(caption: String?, items: [PlaceSpot])   // themed fight diagram (Webbed Cave)
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
        case let .places(caption, items):
            return ((caption.map { [$0] } ?? []) + items.map(\.plainText)).joined(separator: " ")
        }
    }

    // Tagged Codable
    private enum CodingKeys: String, CodingKey {
        case kind, text, items, title, body, tier, headers, rows, key, columns, targets, caption
    }
    private enum Kind: String, Codable {
        case heading, paragraph, bullets, callout, table, image, steps, cards, chips, crossLink, places
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
        case .places:
            self = .places(caption: try? c.decode(String.self, forKey: .caption),
                           items: try c.decode([PlaceSpot].self, forKey: .items))
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
        case let .places(caption, items):
            try c.encode(Kind.places, forKey: .kind)
            try c.encodeIfPresent(caption, forKey: .caption)
            try c.encode(items, forKey: .items)
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
final class LibraryStore {
    var books: [Book] = []
    var error: String?

    func book(_ id: String) -> Book? { books.first { $0.info.id == id } }

    /// Resolve a section id ACROSS THE WHOLE LIBRARY — the seam `crossLink` pills use to
    /// render labels from live section titles. Section ids are unique library-wide, so
    /// one global lookup keeps the entire block layer (RuleSectionDetail, CrossLinkRow)
    /// exactly as it was. A bad/renamed id returns nil and the pill is dropped.
    func section(_ id: String) -> RuleSection? {
        books.lazy.flatMap(\.sections).first { $0.id == id }
    }

    /// Read library.json (the catalog), then load each book's `<id>.json` and assemble.
    /// rulebook.json is just the first entry's file — no special-casing.
    func load() {
        guard let catalogURL = Bundle.main.url(forResource: "library", withExtension: "json") else {
            error = "library.json not found in bundle."
            return
        }
        do {
            let catalog = try JSONDecoder().decode(BookCatalog.self, from: Data(contentsOf: catalogURL))
            books = try catalog.books.map { info in
                guard let url = Bundle.main.url(forResource: info.id, withExtension: "json") else {
                    throw LoadError.missingFile(info.id)
                }
                let file = try JSONDecoder().decode(BookFile.self, from: Data(contentsOf: url))
                return Book(info: info, sections: file.sections)
            }
        } catch {
            self.error = "Failed to load library: \(error)"
        }
    }

    private enum LoadError: LocalizedError {
        case missingFile(String)
        var errorDescription: String? {
            switch self {
            case .missingFile(let id):
                "Book '\(id)' is listed in library.json but \(id).json isn't in the bundle."
            }
        }
    }
}
