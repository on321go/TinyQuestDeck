//  ShopView.swift
//  The Dungeon Shop screen. Pure binding over the systems already built:
//   • shop.cards(repo:)              → the category-card grid (weapons row / rotating row)
//   • ShopRules.shortfall / grant    → affordability + what a purchase becomes
//   • CharacterChoices.receive       → the buy landing on the selected hero
//
//  Shelf is SHARED; the wallet is per-hero — a shopper picker (defaulting to the active
//  hero) chooses whose gold is spent and whose inventory grows. Card = category; tapping
//  pushes a detail listing that category's stocked items, each with its own price + Buy.
//
//  Art: each card floats a category prop over its pastel ground (the mock's overhang
//  look), keyed `shop-<category>` with an SF Symbol fallback — so you can drop art in one
//  category at a time (shop-finesse, shop-potions, …) and undrawn ones keep the symbol.
//  Titles are shown for now because the symbol placeholders don't name themselves; once
//  real per-category art lands you can drop them to match the pure-art mock exactly.

import SwiftUI

private enum ShopMetrics {
    static let cardHeight: CGFloat = 210
    static let artWidth: CGFloat = 130
    static let artPeek: CGFloat = 22
}

struct ShopView: View {
    let repo: ContentRepository
    let roster: RosterStore
    let shop: ShopStore

    @State private var shopperID: UUID?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 3)

    init(repo: ContentRepository, roster: RosterStore, shop: ShopStore, activeHeroID: UUID?) {
        self.repo = repo
        self.roster = roster
        self.shop = shop
        _shopperID = State(initialValue: activeHeroID)
    }

    /// The hero being shopped for — the picked one, or the first hero as a fallback.
    private var shopper: CharacterChoices? {
        roster.characters.first { $0.id == shopperID } ?? roster.characters.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if roster.characters.isEmpty {
                    emptyRoster
                } else {
                    content
                }
            }
            //.padding(.vertical, 30)
            .background(Color.white)
            .navigationDestination(for: ShopCard.self) { card in
                ShopCardDetailView(card: card, repo: repo, roster: roster, shopperID: shopperID)
            }
            .padding(.vertical, 30)
        }
        
        .onAppear { shop.ensureStocked(repo: repo) }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach(shop.cards(repo: repo)) { card in
                        categoryCard(card)
                    }
                    .padding(20)
                }
            }
            .padding(10)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Header — SHOP banner + shopper/wallet picker

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(hex: "AEC3E0"))
                    .frame(height: 74)
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.15), lineWidth: 2))
                QuestChip(text: "Shop", size: 24)
            }
            shopperStrip
        }
    }

    private var shopperStrip: some View {
        HStack(spacing: 12) {
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
            Spacer()
            if showRestockDevControl {
                Button { shop.restock(repo: repo) } label: {
                    Label("Restock", systemImage: "arrow.clockwise")
                        .font(questFont(14)).foregroundStyle(.black.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.3), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Dev affordance: force a restock without waiting on the 8AM/5PM schedule. Mirrors
    // the sheet's temporary gold steppers — flip off when the earning loop is real.
    private let showRestockDevControl = true

    private func shopperPill(_ c: CharacterChoices) -> some View {
        let (bg, accent) = themeColors(c)
        return HStack(spacing: 10) {
            QuestArt(name: portraitName(c), ratio: QuestRatio.card, colors: [accent, bg],
                     symbol: emblemSymbol(deriveSheet(from: c, using: repo)?.theme?.emblem),
                     caption: nil, framed: true)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(questFont(15)).foregroundStyle(.black).lineLimit(1)
                goldLabel(c.gold, size: 13)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption).foregroundStyle(.black.opacity(0.4))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black, lineWidth: 2))
    }

    // MARK: Category card

    private func categoryCard(_ card: ShopCard) -> some View {
        let tint = cardTint(card.category)
        let minPrice = card.items.map(\.cost).min() ?? 0
        return NavigationLink(value: card) {
            VStack(spacing: 6) {
                Spacer()
                Text(card.title)
                    .font(questFont(16)).foregroundStyle(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
                goldLabel(minPrice, size: 13, prefix: "from ")
            }
            .frame(maxWidth: .infinity)
            .frame(height: ShopMetrics.cardHeight, alignment: .bottom)
            .padding(.bottom, 16)
            .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.black, lineWidth: 2))
            .overlay(alignment: .top) {
                QuestArt(name: "shop-\(card.category.rawValue)", ratio: 1,
                         colors: [tint, .white],
                         symbol: categorySymbol(card.category), caption: nil, framed: false)
                    .frame(width: ShopMetrics.artWidth)
                    .offset(y: -ShopMetrics.artPeek)
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

// MARK: - Category detail (lists the stocked items; price + Buy per row)

private struct ShopCardDetailView: View {
    let card: ShopCard
    let repo: ContentRepository
    let roster: RosterStore
    let shopperID: UUID?

    @State private var toast: String?
    private let accent = Color(hex: "6B4E8E")

    private var shopper: CharacterChoices? {
        roster.characters.first { $0.id == shopperID } ?? roster.characters.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = shopper {
                    HStack {
                        Text(card.title).font(questFont(24)).foregroundStyle(.black)
                        Spacer()
                        goldLabel(c.gold, size: 16)
                    }
                    .padding(.bottom, 2)
                }
                ForEach(card.items) { p in
                    itemRow(p)
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(cardTint(card.category).opacity(0.3))
        .navigationTitle(card.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { toastView }
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast)
                .font(questFont(16)).foregroundStyle(.black)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(TierColor.selectPeach, in: Capsule())
                .overlay(Capsule().strokeBorder(.black, lineWidth: 2))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation { self.toast = nil }
                }
        }
    }

    private func itemRow(_ p: Purchasable) -> some View {
        let short = shopper.flatMap { ShopRules.shortfall(buying: p, hero: $0) }
        return HStack(alignment: .top, spacing: 16) {
            purchasableArt(p)
                .frame(width: 190, height: 190)          // image, tripled, top-left
            VStack(alignment: .leading, spacing: 8) {
                infoLabel(p)
                if case .item(let i) = p, i.kind == .scroll, let c = shopper {
                    Text(ShopRules.isCaster(c, repo: repo)
                         ? "\(c.name) can study this to learn the spell."
                         : "\(c.name) can't learn spells — they'll carry it as a one-shot scroll.")
                        .font(questFontLight(13)).foregroundStyle(.black.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(alignment: .center, spacing: 12) {
                    goldLabel(p.cost, size: 18)
                    Spacer()
                    buyButton(p, short: short)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        }
        .padding(18)
        .background(TierColor.panelCream, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 2))
    }

    @ViewBuilder private func infoLabel(_ p: Purchasable) -> some View {
        switch p {
        case .gear(let g):
            TapInfo(payload: .init(gear: g, tint: accent)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.name).font(questFont(20)).foregroundStyle(.black)
                    if let line = gearLine(g) {
                        Text(line).font(.callout.monospaced()).foregroundStyle(.black.opacity(0.55))
                    }
                    if let flavor = g.flavor {
                        Text(flavor).font(questFontLight(13)).foregroundStyle(TierColor.signature)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .item(let i):
            VStack(alignment: .leading, spacing: 4) {
                Text(i.name).font(questFont(20)).foregroundStyle(.black)
                Text(i.text).font(questFontLight(14)).foregroundStyle(.black.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func purchasableArt(_ p: Purchasable) -> some View {
        let cat = ShopCategory.category(of: p)
        let name: String = { switch p { case .gear(let g): "gear-\(g.id)"; case .item(let i): "item-\(i.id)" } }()
        return QuestArt(name: name, ratio: 1, colors: [cardTint(cat), .white],
                        symbol: categorySymbol(cat), caption: nil, framed: false)
    }

    private func buyButton(_ p: Purchasable, short: Int?) -> some View {
        let disabled = shopper == nil || short != nil
        return Button { buy(p) } label: {
            Text(short.map { "Need \($0)g" } ?? "Buy")
                .font(questFont(15)).foregroundStyle(disabled ? .black.opacity(0.4) : .black)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(disabled ? Color.gray.opacity(0.2) : TierColor.selectPeach,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.black.opacity(disabled ? 0.25 : 1), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// The canonical buy: gold-gated, resolve the grant for THIS buyer (scrolls fork on
    /// caster-ness), deduct, land it, persist through the roster's single write path.
    private func buy(_ p: Purchasable) {
        guard var c = shopper, ShopRules.shortfall(buying: p, hero: c) == nil else { return }
        let grant = ShopRules.grant(for: p, buyer: c, repo: repo)
        c.gold -= p.cost
        c.receive(grant)
        roster.update(c)
        withAnimation { toast = "\(c.name) bought \(p.name)!" }
    }
}

// MARK: - File-private shared bits (used by both the grid and the detail)

/// A little gold coin + amount, optionally prefixed ("from ").
private func goldLabel(_ amount: Int, size: CGFloat, prefix: String = "") -> some View {
    HStack(spacing: 4) {
        if !prefix.isEmpty {
            Text(prefix).font(questFontLight(size)).foregroundStyle(.black.opacity(0.55))
        }
        Circle().fill(Color(hex: "E8B923"))
            .frame(width: size + 5, height: size + 5)
            .overlay(Circle().strokeBorder(Color(hex: "B5860B"), lineWidth: 1.5))
        Text("\(amount)").font(questFont(size)).foregroundStyle(Color(hex: "C79008"))
    }
}

/// Pastel ground per category (the mock's per-card colors). Purely presentational —
/// lives here, not on the domain enum.
private func cardTint(_ c: ShopCategory) -> Color {
    switch c {
    case .heavyWeapons:    Color(hex: "D9C7B4")
    case .heavyOneHanders: Color(hex: "C7CEEA")
    case .finesse:         Color(hex: "D8C8EA")
    case .rangedWeapons:   Color(hex: "CBE3C6")
    case .smallRanged:     Color(hex: "CDE7E0")
    case .magicWeapons:    Color(hex: "CDBBDE")
    case .armor:           Color(hex: "C9D5E2")
    case .shields:         Color(hex: "E2D4C2")
    case .potions:         Color(hex: "CBE8DA")
    case .magicItems:      Color(hex: "CFE0EE")
    case .scrolls:         Color(hex: "F0E7CC")
    }
}

/// SF Symbol fallback shown until `shop-<category>` art is drawn.
private func categorySymbol(_ c: ShopCategory) -> String {
    switch c {
    case .heavyWeapons:    "hammer.fill"
    case .heavyOneHanders: "hammer.fill"
    case .finesse:         "scissors"
    case .rangedWeapons:   "figure.archery"
    case .smallRanged:     "figure.archery"
    case .magicWeapons:    "wand.and.stars"
    case .armor:           "shield.lefthalf.filled"
    case .shields:         "shield.fill"
    case .potions:         "drop.fill"
    case .magicItems:      "sparkles"
    case .scrolls:         "scroll.fill"
    }
}

private func statWord(_ s: Stat) -> String {
    switch s { case .might: "Might"; case .speed: "Speed"; case .mind: "Mind" }
}

/// A compact stat line for a gear row ("d20 + Might · d6", "auto-hit · d6 + Speed",
/// "+2 Max HP"). Kept local — the sheet's own summary is private to that file.
private func gearLine(_ g: GearDefinition) -> String? {
    guard let atk = g.attack else {
        return g.maxHP != 0 ? "+\(g.maxHP) Max HP" : nil
    }
    let hit = atk.toHitStat.map { "d20 + \(statWord($0))" } ?? "auto-hit"
    let dice = atk.damageDice.count == 1 ? "d\(atk.damageDice.faces)" : "\(atk.damageDice.count)d\(atk.damageDice.faces)"
    let dmgStat = atk.damageStat.map { " + \(statWord($0))" } ?? ""
    return "\(hit) · \(dice)\(dmgStat)"
}
