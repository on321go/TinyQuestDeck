//  RulebookBrowse.swift
//  Read-only "Browse Classes" / "Browse Kinds" for the rulebook. REUSES the creation
//  screens (PickPathView / PathDetailView / PickKindView / KindDetailView) in browse
//  mode: draft = nil, onSelect drives an internal path (no Select button, no hero
//  commit). Reads live content.json — no data duplicated.
//
//  Presented as a fullScreenCover from the Books tab (its OWN NavigationStack), so it
//  never nests inside the rulebook's stack — nesting stacks breaks push navigation.
//  The pickers navigate via their onSelect CLOSURE (not NavigationLink values), so the
//  browse view owns an explicit path array and appends to it.

import SwiftUI

// MARK: - Browse Classes (Pick a Path → Path Detail, read-only)

struct BrowseClassesView: View {
    let repo: ContentRepository
    var onClose: () -> Void
    @State private var path: [String] = []          // pathIDs being viewed
        /// compact = phone browse: same read-only wiring, phone creation screens.
        /// Their onSelect defaults to nil, so the SELECT bar never renders here.
        @Environment(\.horizontalSizeClass) private var hSize

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if hSize == .compact {
                        PickPathPhoneView(repo: repo) { pathID in path.append(pathID) }   // draft nil → browse
                    } else {
                        PickPathView(repo: repo) { pathID in path.append(pathID) }        // draft nil → browse
                    }
                }
                .navigationTitle("Classes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onClose).font(questFont(16))
                    }
                }
                .navigationDestination(for: String.self) { pathID in
                    Group {
                        if hSize == .compact {
                            PathDetailPhoneView(repo: repo, pathID: pathID)   // onSelect nil → no Select
                        } else {
                            PathDetailView(repo: repo, pathID: pathID)        // onSelect nil → no Select
                        }
                    }
                    .navigationTitle(repo.path(pathID)?.name ?? "Path")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
}

// MARK: - Browse Kinds (Pick a Kind → Kind Detail, read-only)

struct BrowseKindsView: View {
    let repo: ContentRepository
    var onClose: () -> Void
    @State private var path: [String] = []          // raceIDs being viewed
        /// compact = phone browse: same read-only wiring, phone creation screens.
        @Environment(\.horizontalSizeClass) private var hSize

        var body: some View {
            NavigationStack(path: $path) {
                Group {
                    if hSize == .compact {
                        PickKindPhoneView(repo: repo) { raceID in path.append(raceID) }   // draft nil → browse
                    } else {
                        PickKindView(repo: repo) { raceID in path.append(raceID) }        // draft nil → browse
                    }
                }
                .navigationTitle("Kinds")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done", action: onClose).font(questFont(16))
                    }
                }
                .navigationDestination(for: String.self) { raceID in
                    Group {
                        if hSize == .compact {
                            KindDetailPhoneView(repo: repo, raceID: raceID)   // onSelect nil → no Select
                        } else {
                            KindDetailView(repo: repo, raceID: raceID)        // onSelect nil → no Select
                        }
                    }
                    .navigationTitle(repo.race(raceID)?.name ?? "Kind")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
}

// MARK: - Books-tab entry card

/// A rulebook landing card that opens a browsable gallery (Classes / Kinds).
/// Chrome MIRRORS `SectionCard` in RulebookView.swift — same cream panel, same height,
/// same art poking above the top-left corner — so the Browse ground and the two
/// section grounds read as one grid. Both cards take their numbers from `RuleStyle`;
/// retune there, not here, and the two can't drift apart.
/// The leading art is QuestArt (asset `artKey`), falling back to the SF Symbol
/// `icon` until that art is drawn.
struct BrowseCard: View {
    let title: String
    let subtitle: String
    let icon: String            // SF Symbol fallback
    let artKey: String          // catalog asset name, e.g. "browse-classes"
    let accent: Color           // placeholder-gradient hue until the art is drawn

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(questFont(18)).foregroundStyle(.black)
                Text(subtitle).font(questFontLight(14)).foregroundStyle(.black.opacity(0.6))
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.body).foregroundStyle(.black.opacity(0.3))
        }
        .padding(.leading, RuleStyle.iconSize + 8)     // reserve space for the overhanging icon
        .padding(.trailing, 16)
        .frame(height: RuleStyle.cardHeight)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2.5))
        // Art overhangs the top-left, poking above the box — same treatment as SectionCard.
        .overlay(alignment: .topLeading) {
            QuestArt(name: artKey, ratio: 1,
                     colors: [accent, accent.opacity(0.5)],
                     symbol: icon, caption: nil, framed: false)
                .frame(width: RuleStyle.iconSize + 18, height: RuleStyle.iconSize + 18)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                .offset(x: -6, y: -16)
        }
    }
}
