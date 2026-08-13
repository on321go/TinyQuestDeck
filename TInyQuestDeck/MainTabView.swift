//  MainTabView.swift
//  The app root and the mockup's bottom bar: Character Sheet / Heroes / Books /
//  Spells / Shop. The creation flow is a fullScreenCover ABOVE the tabs (no bar
//  during creation, per design); finishing creation selects the new hero and
//  jumps to the Character Sheet tab.
//
//  Make this the root: WindowGroup { MainTabView() }
//  Books / Spells / Shop are styled stubs — built after the sheet settles.

import SwiftUI

// RosterStore lives in CharacterBuilder.swift; the sheet needs in-place updates.
//extension RosterStore {
//    func update(_ c: CharacterChoices) {
//        if let i = characters.firstIndex(where: { $0.id == c.id }) { characters[i] = c }
//    }
//}

enum MainTab: Hashable { case sheet, heroes, books, spells, shop, gm }

struct MainTabView: View {
    @State private var content = ContentStore()
    @State private var roster = RosterStore()
    @State private var combat = CombatStore()
    @State private var libraryStore = LibraryStore()
    @State private var shop = ShopStore()
    @State private var gm = GMStore()
    @State private var party = GMPartyStore()
    @State private var encounters = EncounterStore()
    @State private var adventureStore = AdventureStore()
    @State private var tab: MainTab = .heroes
    @State private var selectedHeroID: UUID? = nil
    @State private var building = false
    @AppStorage("hasEverCreatedHero") private var hasEverCreatedHero = false
    /// compact = iPhone (and iPad Split View / Slide Over): the GM tab renders its
    /// phone variants. The iPad views are untouched — they're just not selected here.
    @Environment(\.horizontalSizeClass) private var hSize
    

    var body: some View {
        Group {
            if let repo = content.repo {
                tabs(repo)
            } else if let error = content.error {
                ScrollView {
                    Text(error).font(.callout.monospaced()).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            } else {
                ProgressView("Loading content…")
            }
        }
        .onAppear { if content.repo == nil && content.error == nil { content.load() } }
        .fullScreenCover(isPresented: $building) {
            if let repo = content.repo {
                if hSize == .compact {
                    CreationFlowPhoneView(repo: repo) { newHero in
                        roster.add(newHero)
                        selectedHeroID = newHero.id
                        tab = .sheet
                        building = false
                        hasEverCreatedHero = true
                    }
                } else {
                    CreationFlowView(repo: repo) { newHero in
                        roster.add(newHero)
                        selectedHeroID = newHero.id
                        tab = .sheet
                        building = false
                        hasEverCreatedHero = true
                    }
                }
            }
        }
    }
    
    private func tabs(_ repo: ContentRepository) -> some View {
        TabView(selection: $tab) {
            Tab("Character Sheet", systemImage: "person.text.rectangle", value: .sheet) {
                if hSize == .compact {
                    CharacterSheetPhoneView(repo: repo, roster: roster, combat: combat, gm: gm,
                                            characterID: selectedHeroID ?? UUID())
                } else {
                    CharacterSheetView(repo: repo, roster: roster, combat: combat, gm: gm,
                                       characterID: selectedHeroID ?? UUID())
                }
            }
            Tab("Heroes", systemImage: "person.3.fill", value: .heroes) {
                HeroesTab(repo: repo, roster: roster,
                          onOpen: { id in selectedHeroID = id; tab = .sheet },
                          onNew: { building = true },
                          onLearnToPlay: { tab = .books })
            }
            Tab("Books", systemImage: "book.fill", value: .books) {
                LibraryView(store: libraryStore, repo: repo)
            }
            //            Tab("Spells", systemImage: "sparkles", value: .spells) {
            //                ComingSoonTab(title: "Spells", symbol: "sparkles",
            //                              blurb: "Every spell, for quick reference mid-game.")
            //            }
            Tab("Shop", systemImage: "bag.fill", value: .shop) {
                if hSize == .compact {
                    ShopPhoneView(repo: repo, roster: roster, shop: shop, combat: combat, activeHeroID: selectedHeroID)
                } else {
                    ShopView(repo: repo, roster: roster, shop: shop, combat: combat, activeHeroID: selectedHeroID)
                }
            }
            Tab("GM", systemImage: "crown.fill", value: .gm) {
                if hSize == .compact {
                    GMPhoneView(repo: repo, roster: roster, gm: gm,
                                party: party, encounters: encounters,
                                adventures: adventureStore, library: libraryStore)
                } else {
                    GMView(repo: repo, roster: roster, gm: gm,
                           party: party, encounters: encounters,
                           adventures: adventureStore, library: libraryStore)
                }
            }
        }
    }
}

// MARK: - Heroes tab (roster grid; independent of the old HeroGrid)

struct HeroesTab: View {
    let repo: ContentRepository
    let roster: RosterStore
    var onOpen: (UUID) -> Void
    var onNew: () -> Void
    var onLearnToPlay: () -> Void
    
    // Real newcomer signal: has this user ever finished creating a hero? Written
    // at the creation choke point in MainTabView, read here. No onAppear, no
    // self-gating — set by an action, not by this view appearing.
    @AppStorage("hasEverCreatedHero") private var hasEverCreatedHero = false
    @State private var showWelcome = false
    
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    QuestChip(text: "Heroes", size: 22)
                    Spacer()
                    Button { showWelcome = true } label: {
                        Label("Starting Info", systemImage: "questionmark.circle.fill")
                            .font(questFont(16)).foregroundStyle(.black)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    Button(action: onNew) {
                        Label("New Hero", systemImage: "plus.circle.fill")
                            .font(questFont(16)).foregroundStyle(.black)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                
                if roster.characters.isEmpty {
                    if hasEverCreatedHero {
                        ContentUnavailableView {
                            Label("No heroes yet", systemImage: "person.crop.circle.badge.plus")
                        } description: {
                            Text("Tap New Hero to step through the portal, or Starting Info for a refresher.")
                        }
                        .padding(.top, 60)
                    } else {
                        WelcomeView(onCreateHero: onNew, onLearnToPlay: onLearnToPlay)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(roster.characters) { c in
                            Button { onOpen(c.id) } label: { heroTile(c) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete \(c.name)", role: .destructive) {
                                        if let i = roster.characters.firstIndex(where: { $0.id == c.id }) {
                                            roster.remove(at: IndexSet(integer: i))
                                        }
                                    }
                                }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
      .background(Color.white)
      .sheet(isPresented: $showWelcome) {
          WelcomeView(
              onCreateHero: { showWelcome = false; onNew() },
              onLearnToPlay: { showWelcome = false; onLearnToPlay() },
              onClose: { showWelcome = false }
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .presentationDetents([.medium, .large])
      }
  }

    private func heroTile(_ c: CharacterChoices) -> some View {
        let sheet = deriveSheet(from: c, using: repo)
        let bg = sheet?.theme.map { Color(hex: $0.background) } ?? .gray
        let accent = sheet?.theme.map { Color(hex: $0.accent) } ?? .blue
        return VStack(alignment: .leading, spacing: 8) {
            QuestArt(name: portraitName(c),
                                 ratio: QuestRatio.card,
                                 colors: [accent, bg],
                                 symbol: emblemSymbol(sheet?.theme?.emblem),
                                 caption: nil,
                                 framed: true)
            Text(c.name.uppercased())
                .font(questFont(16)).foregroundStyle(.black)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let sheet {
                Text("Lv \(sheet.level) · \(sheet.raceName) \(sheet.pathName)")
                    .font(questFontLight(13)).foregroundStyle(.black.opacity(0.65))
            }
        }
        .padding(12)
        .background(bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }
    
    /// The hero's chosen portrait (or the race×class default) — same resolution the
        /// character sheet uses, so card and sheet always match.
        private func portraitName(_ c: CharacterChoices) -> String {
            let combo = c.portraitID
                ?? QuestArtKey.portraitCombo(race: c.raceID, klass: c.classID)
            return QuestArtKey.portrait(combo: combo)
        }
}

// MARK: - Styled stub for the three future tabs

struct ComingSoonTab: View {
    let title: String
    let symbol: String
    let blurb: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: "8A7BB8"))
            Text(title.uppercased()).font(questFont(28)).foregroundStyle(.black)
            Text(blurb).font(questFontLight(16)).foregroundStyle(.black.opacity(0.6))
            Text("Coming soon!").font(questFont(15)).foregroundStyle(TierColor.signature)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - First-run welcome / routing
// Shown inline on an empty Heroes tab AND from the "Starting Info" button.
// Built once; each site supplies the closures. onClose nil = inline (no dismiss
// control); non-nil = sheet (renders an ×). The auto/flag logic lives at the
// call site, never here.

struct WelcomeView: View {
    var onCreateHero: () -> Void
    var onLearnToPlay: () -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(spacing: 12) {
                routeButton(title: "Create your first hero",
                            symbol: "person.crop.circle.badge.plus",
                            fill: TierColor.selectPeach, action: onCreateHero)
                routeButton(title: "Learn to play",
                            symbol: "book.fill",
                            fill: Color(hex: "E8E2F4"), action: onLearnToPlay)
            }
            grownUpLine
        }
        .padding(24)
        .frame(maxWidth: 460)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.black, lineWidth: 2))
        .overlay(alignment: .topTrailing) { closeControl }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuestChip(text: "Welcome", size: 22)
            Text("Two taps to your first adventure.")
                .font(questFontLight(16)).foregroundStyle(.black.opacity(0.65))
        }
    }

    private func routeButton(title: String, symbol: String,
                             fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                Text(title).font(questFont(17))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black.opacity(0.4))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var grownUpLine: some View {
        Text("Playing with a grown-up? They run the Game Master tab.")
            .font(questFontLight(14)).foregroundStyle(.black.opacity(0.55))
            .padding(.top, 2)
    }

    @ViewBuilder private var closeControl: some View {
        if let onClose {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(.black.opacity(0.35))
                    .padding(12)
            }
            .buttonStyle(.plain)
        }
    }
}
