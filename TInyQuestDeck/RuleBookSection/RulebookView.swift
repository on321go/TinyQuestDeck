//  RulebookView.swift
//  The in-app rulebook reader (Books tab). App visual language — marker font, cream
//  panels, black-outline cards. Blue is the central accent; each section group gets a
//  soft page tint (Player = green family, GM = purple family) so the cream panels
//  never float on raw white and the tint tells you which half of the book you're in.
//
//  Depends on Rulebook.swift, QuestStyle.swift, Color(hex:).

import SwiftUI

// MARK: - Tunable palette (one place to retune the reader's look)

// NOTE: intentionally NOT private — RulebookBrowse.swift's BrowseCard mirrors
// SectionCard's chrome and must read the same numbers. This stays the one place to
// retune the reader's look.
enum RuleStyle {
    static let blue        = Color(hex: "A8CBE4")   // central accent (New Hero name bar)
    static let blueInk     = Color(hex: "3E6E96")   // darker blue for header text on cream

    // Soft per-group page tints (behind the cream panels).
    static let playerPage  = Color(hex: "CDE3BE")   // green family
    static let gmPage      = Color(hex: "C9C4EC")   // purple family
    static let browsePage  = Color(hex: "BCDCF0")   // blue family — the Browse ground
    static let pageTint    = 0.45                    // opacity of the page tint

    // Table
    static let zebra        = Color(hex: "F3EBC9")   // stripe (warm; swap to blue-tinted to try that)
    static let zebraOpacity = 0.55

    // Richer, more saturated callout tiers
    static let calloutGreen  = Color(hex: "2E9E4F")
    static let calloutPurple = Color(hex: "8A4FD0")
    static let calloutOrange = Color(hex: "F0821E")

    static let cardHeight: CGFloat = 88             // ~25% taller than the old ~70
    static let iconSize: CGFloat   = 46             // ~2x the old 26

    // Action-economy colors (SPEC §2.1). Page-local visual aid for the Big Idea's
    // economy block — deliberately NOT a global contract, so the overlap with the
    // green/purple page tints above is known and accepted.
    struct Economy { let fill: Color; let ink: Color; let badge: Color }
    static func economy(_ c: EconomyColor?) -> Economy {
        switch c ?? .plain {
        case .move:     Economy(fill: Color(hex: "E6F1FB"), ink: Color(hex: "0C447C"), badge: Color(hex: "B5D4F4"))
        case .thing:    Economy(fill: Color(hex: "FAECE7"), ink: Color(hex: "8A3417"), badge: Color(hex: "F5C4B3"))
        case .free:     Economy(fill: Color(hex: "EAF3DE"), ink: Color(hex: "2F600E"), badge: Color(hex: "C0DD97"))
        case .reaction: Economy(fill: Color(hex: "EEEDFE"), ink: Color(hex: "3C3489"), badge: Color(hex: "CECBF6"))
        case .plain:    Economy(fill: TierColor.panelCream, ink: .black, badge: blue)
        }
    }
}

// MARK: - Root (Books tab)
// MARK: - Level 1: the library (Books tab root)
//
// The Books tab is two levels now. This is level 1 — a grid of book covers derived
// from LibraryStore.books (library.json). It owns the tab's ONE NavigationStack and
// registers BOTH destinations: a Book pushes its detail (level 2), a RuleSection
// pushes its reader (level 3). Nothing is hardcoded to the rulebook — add a book to
// library.json and it appears.

struct LibraryView: View {
    let store: LibraryStore
    let repo: ContentRepository

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    QuestChip(text: "Books", fill: RuleStyle.blue, size: 22)
                    if let error = store.error {
                        Text(error).font(.callout.monospaced()).foregroundStyle(.red)
                    } else {
                        pageGround("Your Books", tint: RuleStyle.browsePage) { booksGrid }
                    }
                }
                .padding(20)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book, store: store, repo: repo)
            }
            .navigationDestination(for: RuleSection.self) { section in
                RuleSectionDetail(section: section, store: store)
            }
        }
        .onAppear { if store.books.isEmpty && store.error == nil { store.load() } }
    }

    // Covers reuse BrowseCard's chrome (cream card, overhanging art) so level 1 reads
    // as the same grid family as the section cards inside. Cover art is a QuestArt
    // keyed by the catalog's coverArt, SF-Symbol fallback until it's drawn.
    private var booksGrid: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(store.books) { book in
                NavigationLink(value: book) {
                    BookCoverCard(info: book.info)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Book cover card (level-1 list tile)
//
// The books' OWN card — deliberately not BrowseCard, so retuning the list here never
// touches the deck-browser tiles that reuse BrowseCard. Uses a real 5:7 cover thumb
// (framed → clipped, book-shaped) instead of the small overhanging emblem. This is the
// seam to grow into a taller portrait cover for the 2-column book-grid look later.

private struct BookCoverCard: View {
    let info: BookInfo

    var body: some View {
        HStack(spacing: 16) {
            QuestArt(name: info.coverArt, ratio: QuestRatio.card,
                     colors: [RuleStyle.blue, RuleStyle.blue.opacity(0.5)],
                     symbol: info.coverSymbol, caption: nil, framed: false)
            .frame(width: 88)                 // 5:7 → ~123 tall                // 5:7 → ~123 tall
            
            VStack(alignment: .leading, spacing: 8) {
                Text(info.title)
                    .font(questFont(20)).foregroundStyle(.black)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(info.blurb)
                    .font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                    .lineLimit(3).minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.body).foregroundStyle(.black.opacity(0.3))
        }
        .padding(14)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2.5))
    }
}

/// The tinted page ground: titled card field behind a grid. One helper so every ground
/// (Library / Browse / Player / GM) can only ever differ by title and hue. Free
/// function (was a method on the old root) so both levels share it.
private func pageGround<Content: View>(_ title: String,
                                       tint: Color,
                                       @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text(title.uppercased()).font(questFont(18)).foregroundStyle(.black.opacity(0.8))
        content()
            .padding(.top, 8)   // room for the first row's poking icons
    }
    .padding(16)
    .background(tint.opacity(RuleStyle.pageTint),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
}

// MARK: - Level 2: one book's sections (was the Books-tab root)

struct BookDetailView: View {
    let book: Book
    let store: LibraryStore
    let repo: ContentRepository
    @State private var query = ""
    @State private var browsing: BrowseTarget? = nil

    enum BrowseTarget: Identifiable { case classes, kinds; var id: Self { self } }

    private var results: [RuleSection] { book.sections(matching: query) }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                QuestChip(text: book.title, fill: RuleStyle.blue, size: 22)

                searchField

                if let error = store.error {
                    Text(error).font(.callout.monospaced()).foregroundStyle(.red)
                } else if searching {
                    resultsGrid
                } else {
                    if book.showsDeckBrowser { browseRow }
                    group("Playing the Game", book.playerSections, tint: RuleStyle.playerPage)
                    group("For the Game Master", book.gmSections, tint: RuleStyle.gmPage)
                }
            }
            .padding(20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $browsing) { target in
            switch target {
            case .classes: BrowseClassesView(repo: repo) { browsing = nil }
            case .kinds:   BrowseKindsView(repo: repo) { browsing = nil }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(RuleStyle.blueInk)
            TextField("Search the rules…", text: $query)
                .font(questFontLight(17))
                .autocorrectionDisabled()
            if searching {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.black.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RuleStyle.blue, lineWidth: 2.5))
    }

    /// "Browse Classes / Kinds" — read-only galleries reusing the creation screens,
    /// opened as full-screen covers (their own NavigationStack) so they never nest
    /// inside this reader's stack. Rulebook-only, gated by book.showsDeckBrowser.
    private var browseRow: some View {
        pageGround("Browse the Deck", tint: RuleStyle.browsePage) {
            LazyVGrid(columns: columns, spacing: 22) {   // extra row spacing so icons can poke up
                Button { browsing = .classes } label: {
                    BrowseCard(title: "Browse Classes",
                               subtitle: "See every class and path",
                               icon: "shield.lefthalf.filled", artKey: "browse-classes",
                               accent: RuleStyle.blue)
                }
                .buttonStyle(.plain)

                Button { browsing = .kinds } label: {
                    BrowseCard(title: "Browse Kinds",
                               subtitle: "Meet all eight kinds",
                               icon: "person.3.fill", artKey: "browse-kinds",
                               accent: RuleStyle.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ sections: [RuleSection], tint: Color) -> some View {
        if !sections.isEmpty {
            pageGround(title, tint: tint) {
                LazyVGrid(columns: columns, spacing: 22) {   // extra row spacing so icons can poke up
                    ForEach(sections) { section in
                        NavigationLink(value: section) { SectionCard(section: section) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultsGrid: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                .font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(results) { section in
                    NavigationLink(value: section) { SectionCard(section: section) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Section card (grid tile) — bigger, big colored icon poking above the top

private struct SectionCard: View {
    let section: RuleSection

    /// Icon accent by group (blue is the shared brand; icon adds a pop of the group hue).
    private var iconColor: Color {
        section.group == .gm ? RuleStyle.calloutPurple : RuleStyle.calloutGreen
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(section.title)
                .font(questFont(18)).foregroundStyle(.black)
                .lineLimit(2).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.body).foregroundStyle(.black.opacity(0.3))
        }
        .padding(.leading, RuleStyle.iconSize + 8)     // reserve space for the overhanging icon
        .padding(.trailing, 16)
        .frame(height: RuleStyle.cardHeight)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2.5))
        // Icon overhangs the top-left, poking above the box (temporary — will become
        // cartoon art like potion bottles / spellbooks).
        .overlay(alignment: .topLeading) {
            QuestArt(name: "rules-icon-\(section.id)",   // resolves rules-icon-fighting, etc.
                       ratio: 1,                            // square
                       symbol: section.icon,                // SF Symbol fallback until art is drawn
                       caption: nil,
                       framed: false)
                  .frame(width: RuleStyle.iconSize + 18, height: RuleStyle.iconSize + 18)
                  .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                  .offset(x: -6, y: -16)
        }
    }
}

// MARK: - Section detail

struct RuleSectionDetail: View {
    let section: RuleSection
    /// Needed so `crossLink` pills can resolve target ids → live section titles
    /// (labels are never duplicated into rulebook.json) and push them.
    let store: LibraryStore

    private var pageTint: Color {
        (section.group == .gm ? RuleStyle.gmPage : RuleStyle.playerPage)
            .opacity(RuleStyle.pageTint)
    }

    /// Group hue, handed to the blocks that draw structure (step spine, pills).
    private var accent: Color {
        section.group == .gm ? RuleStyle.calloutPurple : RuleStyle.calloutGreen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuestChip(text: section.title, fill: RuleStyle.blue, size: 22)
                ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block, store: store, accent: accent)
                }
            }
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(pageTint.ignoresSafeArea())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Block rendering

private struct BlockView: View {
    let block: RuleBlock
    let store: LibraryStore
    let accent: Color

    var body: some View {
        switch block {
        case .heading(let t):
            Text(t).font(questFont(20)).foregroundStyle(RuleStyle.blueInk)
                .padding(.top, 6)

        case .paragraph(let t):
            Text(t).font(questFontLight(17)).foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}").font(questFont(17)).foregroundStyle(RuleStyle.blueInk)
                        Text(item).font(questFontLight(17)).foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .callout(title, body, tier):
            CalloutBox(title: title, lines: body, tier: tier)

        case let .table(headers, rows):
            RuleTable(headers: headers, rows: rows)

        case .image(let key):
            QuestArt(name: "rules-\(key)", ratio: QuestRatio.banner,
                     symbol: "book.closed.fill", caption: nil)

        case .steps(let items):
            StepsSpine(steps: items, store: store, accent: accent)

        case let .cards(columns, items):
            CardsGrid(columns: columns, items: items)

        case let .chips(title, rows):
            ChipsPanel(title: title, rows: rows)

        case let .crossLink(title, targets):
            CrossLinkRow(title: title, targets: targets, store: store, accent: accent)

        case .unknown:
            EmptyView()
        }
    }
}

private struct CalloutBox: View {
    let title: String
    let lines: [String]
    let tier: CalloutTier

    private var color: Color {
        switch tier {
        case .starting:  RuleStyle.calloutGreen
        case .path:      RuleStyle.calloutPurple
        case .signature: RuleStyle.calloutOrange
        }
    }
    private var icon: String {
        switch tier {
        case .starting:  "lightbulb.fill"
        case .path:      "info.circle.fill"
        case .signature: "star.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(questFont(17)).foregroundStyle(color)
            }
            ForEach(lines, id: \.self) { line in
                Text(line).font(questFontLight(16)).foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color, lineWidth: 2.5))
    }
}

// MARK: - Steps (numbered spine)
//
// The Big Idea's five-step on-ramp and the GM loop share this one renderer (vertical
// spine both times — a 3-beat loop reads fine stacked, and one renderer is one thing
// to retune). A step can nest blocks, which is how the class picker and the whole
// action-economy block sit INSIDE their step, indented on the spine.

private struct StepsSpine: View {
    let steps: [RuleStep]
    let store: LibraryStore
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                StepRow(step: step, isLast: i == steps.count - 1, store: store, accent: accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StepRow: View {
    let step: RuleStep
    let isLast: Bool
    let store: LibraryStore
    let accent: Color

    private let bubble: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Spine: bubble + connector. The connector is a flexible frame, so it
            // stretches to whatever the content column ends up being.
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(accent.opacity(0.35))
                    Circle().strokeBorder(.black, lineWidth: 2)
                    if let icon = step.icon {
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                    } else {
                        Text("\(step.n)").font(questFont(17)).foregroundStyle(.black)
                    }
                }
                .frame(width: bubble, height: bubble)

                if !isLast {
                    Rectangle()
                        .fill(accent.opacity(0.5))
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: bubble)

            VStack(alignment: .leading, spacing: 8) {
                Text(step.title).font(questFont(18)).foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)

                if let body = step.body {
                    Text(body).font(questFontLight(16)).foregroundStyle(.black.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let highlight = step.highlight {
                    HighlightPill(text: highlight, icon: step.highlightIcon, accent: accent)
                }

                if let blocks = step.blocks {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, nested in
                        BlockView(block: nested, store: store, accent: accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 18)
        }
    }
}

/// The one sentence that matters most on the page (THE ONE RULE), in its own pill.
private struct HighlightPill: View {
    let text: String
    let icon: String?
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon).font(.system(size: 17, weight: .bold))
            }
            Text(text).font(questFont(16))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(accent.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Cards (mini-card grid: class picker, GM four-up, action economy)
//
// Deliberately NOT a LazyVGrid: these grids live nested inside a step inside a
// ScrollView, and lazy containers on nested surfaces are the known culling-bug shape
// (see HANDOFF_GM_Interface). Item counts are 4 — laziness buys nothing.

private struct CardsGrid: View {
    let columns: Int
    let items: [RuleCard]

    private var perRow: Int { max(1, columns) }
    private var rows: [[RuleCard]] {
        stride(from: 0, to: items.count, by: perRow).map {
            Array(items[$0 ..< min($0 + perRow, items.count)])
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, card in
                        RuleCardView(card: card)
                    }
                    // Keep the last row's cards the same width as a full row's.
                    if row.count < perRow {
                        ForEach(0 ..< (perRow - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RuleCardView: View {
    let card: RuleCard

    private var style: RuleStyle.Economy { RuleStyle.economy(card.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let icon = card.icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(style.ink)
                }
                Text(card.title).font(questFont(16)).foregroundStyle(style.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let badge = card.badge {
                    Spacer(minLength: 6)
                    Text(badge)
                        .font(questFontLight(12)).foregroundStyle(style.ink)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(style.badge, in: Capsule())
                        .overlay(Capsule().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                        .fixedSize()
                }
            }

            if let text = card.text {
                Text(text).font(questFontLight(15)).foregroundStyle(.black.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let examples = card.examples {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.ink.opacity(0.75))
                        .padding(.top, 3)
                    Text(examples).font(questFontLight(14)).foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }
}

// MARK: - Chips (the sample-turn strip)

private struct ChipsPanel: View {
    let title: String?
    let rows: [RuleChipRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(questFont(15)).foregroundStyle(.black.opacity(0.75))
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ChipFlow(row: row)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
    }
}

private struct ChipFlow: View {
    let row: RuleChipRow

    var body: some View {
        FlowLayout(spacing: 6) {
            if let label = row.label {
                Text(label).font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                    .padding(.vertical, 6)
            }
            ForEach(Array(row.items.enumerated()), id: \.offset) { i, chip in
                if row.joined == true, i > 0 {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.4))
                        .padding(.vertical, 8)
                }
                EconomyChip(chip: chip)
            }
        }
    }
}

private struct EconomyChip: View {
    let chip: RuleChip

    var body: some View {
        let style = RuleStyle.economy(chip.color)
        Text(chip.text)
            .font(questFontLight(14))
            .foregroundStyle(style.ink)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(style.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.55), lineWidth: 1.5))
    }
}

// MARK: - Cross-links (pill row → other sections)
//
// Labels come from the LIVE section titles via the store — the page points, it never
// copies. An id that no longer resolves is dropped rather than rendering a dead pill.

private struct CrossLinkRow: View {
    let title: String?
    let targets: [String]
    let store: LibraryStore
    let accent: Color

    private var sections: [RuleSection] { targets.compactMap { store.section($0) } }

    @ViewBuilder
    var body: some View {
        if !sections.isEmpty {
            FlowLayout(spacing: 8) {
                if let title {
                    Text(title).font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                        .padding(.vertical, 7)
                }
                ForEach(sections) { section in
                    NavigationLink(value: section) {
                        HStack(spacing: 6) {
                            Text(section.title).font(questFont(14)).foregroundStyle(.black)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.black.opacity(0.45))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(accent.opacity(0.35), in: Capsule())
                        .overlay(Capsule().strokeBorder(.black, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - FlowLayout
//
// Minimal wrapping row: chips and pills flow onto the next line instead of squeezing.
// Used by the sample-turn strip and the cross-link pills.

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Table
//
// FIX: previously the first column used a LOWER layoutPriority, so on a wide iPad it
// collapsed to ~zero width -- dropping MIGHT/MIND/SPEED, the rule WORDS, etc. All
// columns now share priority and a min width, so no column vanishes. Rows also hug
// their content (no forced height) instead of stretching to huge empty boxes.

private struct RuleTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        VStack(spacing: 0) {
            row(headers, isHeader: true)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, cells in
                Divider().overlay(.black.opacity(0.15))
                row(cells, isHeader: false, striped: !i.isMultiple(of: 2))
            }
        }
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2.5))
    }

    private func row(_ cells: [String], isHeader: Bool, striped: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(isHeader ? questFont(15) : questFontLight(15))
                    .foregroundStyle(isHeader ? RuleStyle.blueInk : .black.opacity(0.85))
                    .frame(minWidth: 40, maxWidth: .infinity, alignment: .leading)  // equal share; never collapse
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)   // tight -- hugs content
        .background(
            isHeader ? RuleStyle.blue.opacity(0.55)
                     : (striped ? RuleStyle.zebra.opacity(RuleStyle.zebraOpacity) : Color.clear)
        )
    }
}
