//  RulebookView.swift
//  The in-app rulebook reader (Books tab). App visual language — marker font, cream
//  panels, black-outline cards. Blue is the central accent; each section group gets a
//  soft page tint (Player = green family, GM = purple family) so the cream panels
//  never float on raw white and the tint tells you which half of the book you're in.
//
//  Depends on Rulebook.swift, QuestStyle.swift, Color(hex:).

import SwiftUI

// MARK: - Tunable palette (one place to retune the reader's look)

private enum RuleStyle {
    static let blue        = Color(hex: "A8CBE4")   // central accent (New Hero name bar)
    static let blueInk     = Color(hex: "3E6E96")   // darker blue for header text on cream

    // Soft per-group page tints (behind the cream panels).
    static let playerPage  = Color(hex: "CDE3BE")   // green family
    static let gmPage      = Color(hex: "C9C4EC")   // purple family
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
}

// MARK: - Root (Books tab)

struct RulebookView: View {
    let store: RulebookStore
    let repo: ContentRepository
    @State private var query = ""
    @State private var browsing: BrowseTarget? = nil

    enum BrowseTarget: Identifiable { case classes, kinds; var id: Self { self } }

    private var results: [RuleSection] { store.sections(matching: query) }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    QuestChip(text: "Rulebook", fill: RuleStyle.blue, size: 22)

                    searchField

                    if let error = store.error {
                        Text(error).font(.callout.monospaced()).foregroundStyle(.red)
                    } else if searching {
                        resultsGrid
                    } else {
                        browseRow
                        group("Playing the Game", store.playerSections, tint: RuleStyle.playerPage)
                        group("For the Game Master", store.gmSections, tint: RuleStyle.gmPage)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)
            .navigationDestination(for: RuleSection.self) { RuleSectionDetail(section: $0) }
        }
        .onAppear { if store.rulebook == nil && store.error == nil { store.load() } }
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
    /// inside this reader's stack.
    private var browseRow: some View {
        LazyVGrid(columns: columns, spacing: 14) {
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

    @ViewBuilder
    private func group(_ title: String, _ sections: [RuleSection], tint: Color) -> some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title.uppercased()).font(questFont(18)).foregroundStyle(.black.opacity(0.8))
                LazyVGrid(columns: columns, spacing: 22) {   // extra row spacing so icons can poke up
                    ForEach(sections) { section in
                        NavigationLink(value: section) { SectionCard(section: section) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)   // room for the first row's poking icons
            }
            .padding(16)
            .background(tint.opacity(RuleStyle.pageTint),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
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

    private var pageTint: Color {
        (section.group == .gm ? RuleStyle.gmPage : RuleStyle.playerPage)
            .opacity(RuleStyle.pageTint)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                QuestChip(text: section.title, fill: RuleStyle.blue, size: 22)
                ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                    BlockView(block: block)
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
