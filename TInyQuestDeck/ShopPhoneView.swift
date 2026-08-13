//  ShopPhoneView.swift  (iPhone / compact — the Dungeon Shop grid)
//  The main shop screen at phone width. PARALLEL VIEW, NOT A BRANCH: ShopView.swift
//  keeps its three-column iPad grid untouched; MainTabView selects this at compact
//  width.
//
//  WHY: the iPad grid hardcodes THREE flexible columns, so at 390pt each card gets
//  ~110pt — while ShopMetrics.artWidth is 130, making the floating category art
//  WIDER than its own card (the lollipop look). Here: TWO columns, art sized under
//  the column (96pt, 16pt peek), and the grid reserves top clearance for the first
//  row's overhang. The mock's floating-prop look survives, phone-sized.
//
//  Only the GRID screen is a variant. The category detail and Sell screens are
//  row-based and already read fine at phone width (Joey's call), so this view
//  pushes the SAME ShopCardDetailView / SellView the iPad uses (made internal —
//  the CombatantDetail precedent), along with the shared goldLabel/cardTint
//  chrome. One shelf, one wallet, one buy path — nothing forks below the layout.

import SwiftUI

private enum PhoneShop {
    static let cardHeight: CGFloat = 170
    static let artWidth: CGFloat = 96
    static let artPeek: CGFloat = 16
}

struct ShopPhoneView: View {
    let repo: ContentRepository
    let roster: RosterStore
    let shop: ShopStore
    let combat: CombatStore

    @State private var shopperID: UUID?

    private let columns = [GridItem(.flexible(), spacing: 14),
                           GridItem(.flexible(), spacing: 14)]

    init(repo: ContentRepository, roster: RosterStore, shop: ShopStore,
         combat: CombatStore, activeHeroID: UUID?) {
        self.repo = repo
        self.roster = roster
        self.shop = shop
        self.combat = combat
        _shopperID = State(initialValue: activeHeroID)
    }

    /// Same rule as the iPad: the picked hero, or the first as a fallback.
    private var shopper: CharacterChoices? {
        roster.characters.first { $0.id == shopperID } ?? roster.characters.first
    }

    // Mirrors the iPad's dev affordance; retires with the earning loop, both at once.
    private let showRestockDevControl = true

    var body: some View {
        NavigationStack {
            Group {
                if roster.characters.isEmpty {
                    emptyRoster
                } else {
                    content
                }
            }
            .background(Color.white)
            .navigationDestination(for: ShopCard.self) { card in
                // The iPad detail, unchanged — row layouts already fit a phone.
                ShopCardDetailView(card: card, repo: repo, roster: roster, shopperID: shopperID)
            }
        }
        .onAppear { shop.ensureStocked(repo: repo) }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(shop.cards(repo: repo)) { card in
                        categoryCard(card)
                    }
                }
                // Top clearance so the FIRST row's overhanging art never clips
                // against the header (the grid's spacing handles later rows).
                .padding(.top, PhoneShop.artPeek)
            }
            .padding(14)
        }
    }

    // MARK: Header — SHOP banner + shopper/wallet strip

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "AEC3E0"))
                    .frame(height: 58)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.black.opacity(0.15), lineWidth: 2))
                QuestChip(text: "Shop", size: 19)
            }
            shopperStrip
        }
    }

    private var shopperStrip: some View {
        HStack(spacing: 8) {
            if let c = shopper {
                Menu {
                    ForEach(roster.characters) { hero in
                        Button {
                            shopperID = hero.id
                        } label: {
                            Label("\(hero.name) · \(hero.gold)g",
                                  systemImage: hero.id == c.id ? "checkmark" : "person.fill")
                        }
                    }
                } label: {
                    shopperPill(c)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            if showRestockDevControl {
                // Icon-only on the phone — it's a dev control, not table furniture.
                Button { shop.restock(repo: repo) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black.opacity(0.7))
                        .frame(width: 38, height: 38)
                        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.black.opacity(0.3), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                SellView(repo: repo, roster: roster, combat: combat, shopperID: shopperID)
            } label: {
                Label("Sell", systemImage: "tag.fill")
                    .font(questFont(13)).foregroundStyle(.black)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(TierColor.selectPeach, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }

    private func shopperPill(_ c: CharacterChoices) -> some View {
        let (bg, accent) = themeColors(c)
        return HStack(spacing: 8) {
            QuestArt(name: portraitName(c), ratio: QuestRatio.card, colors: [accent, bg],
                     symbol: emblemSymbol(deriveSheet(from: c, using: repo)?.theme?.emblem),
                     caption: nil, framed: true)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(questFont(13)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
                goldLabel(c.gold, size: 12)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2).foregroundStyle(.black.opacity(0.4))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: Category card — art sized UNDER the column, overhang kept

    private func categoryCard(_ card: ShopCard) -> some View {
        let tint = cardTint(card.category)
        let minPrice = card.items.map(\.cost).min() ?? 0
        return NavigationLink(value: card) {
            VStack(spacing: 4) {
                Spacer()
                Text(card.title)
                    .font(questFont(14)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
                goldLabel(minPrice, size: 12, prefix: "from ")
            }
            .frame(maxWidth: .infinity)
            .frame(height: PhoneShop.cardHeight, alignment: .bottom)
            .padding(.bottom, 12)
            .background(tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
            .overlay(alignment: .top) {
                QuestArt(name: "shop-\(card.category.rawValue)", ratio: 1,
                         colors: [tint, .white],
                         symbol: categorySymbol(card.category), caption: nil, framed: false)
                    .frame(width: PhoneShop.artWidth)
                    .offset(y: -PhoneShop.artPeek)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty state

    private var emptyRoster: some View {
        ContentUnavailableView {
            Label("No heroes yet", systemImage: "bag.badge.questionmark")
        } description: {
            Text("Create a hero first, then bring them to the shop to spend their gold.")
        }
    }

    // MARK: Small per-view helpers (portrait + theme need the repo)

    private func portraitName(_ c: CharacterChoices) -> String {
        let combo = c.portraitID ?? QuestArtKey.portraitCombo(race: c.raceID, klass: c.classID)
        return QuestArtKey.portrait(combo: combo)
    }

    private func themeColors(_ c: CharacterChoices) -> (Color, Color) {
        let sheet = deriveSheet(from: c, using: repo)
        let bg = sheet?.theme.map { Color(hex: $0.background) } ?? .gray
        let accent = sheet?.theme.map { Color(hex: $0.accent) } ?? .blue
        return (bg, accent)
    }
}
