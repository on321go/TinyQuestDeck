//  ShopStore.swift
//  The Dungeon Shop's shelf: what's for sale right now, how it restocks, and how the
//  flat stock groups into the grid's category cards. One SHARED shelf for the whole
//  roster (wallets/inventories are per-hero, stock is not).
//
//  Persistence is a single StoredShop row (see Persistence.swift) holding the encoded
//  ShopStock + lastRestock. The store LOADS repo-free (blob decode only); the repo is
//  needed just to first-stock an empty shelf and to run a restock, so those take it as
//  a parameter (call ensureStocked(repo:) from the shop tab once the repo is ready).
//
//  RESTOCK is the one place shop randomness lives — deliberately walled off from any
//  gameplay roll (the no-dice pillar). It shapes the shelf, never a play outcome.
//   • Top row  — 3 DISTINCT weapon families (so the row is never three swords).
//   • Bottom row — 3 categories from the rotating non-weapon pool
//     (armor / shields / potions / magic items / scrolls).
//   • Within each card, items are sampled without replacement (no dupes in a cycle).
//
//  NOTE: ShopCategory.category(of:) mirrors the weapon-family split in
//  CharacterSheetView's private `gearFamily`. Kept separate for now (surgical); worth
//  unifying into one shared classifier when the sheet is next touched.

import Foundation
import SwiftData
import Observation

// MARK: - Stored value types (the blob)

/// A tagged reference into the content catalog. Stock mixes gear and items, so we can't
/// store a bare id. Codable is synthesized (internal blob shape — not hand-authored).
enum PurchasableRef: Codable, Hashable {
    case gear(String)   // GearDefinition.id
    case item(String)   // ItemDefinition.id
}

/// The shelf's current contents: a flat list of stocked refs. Cards are DERIVED at
/// display time, so we never persist layout — only what's in stock.
struct ShopStock: Codable, Hashable {
    var refs: [PurchasableRef]

    static let empty = ShopStock(refs: [])

    func resolve(_ ref: PurchasableRef, repo: ContentRepository) -> Purchasable? {
        switch ref {
        case .gear(let id): repo.gear(id).map(Purchasable.gear)
        case .item(let id): repo.item(id).map(Purchasable.item)
        }
    }

    /// Group the flat stock into category cards, weapons first (top row), then the rest.
    func cards(repo: ContentRepository) -> [ShopCard] {
        let resolved = refs.compactMap { resolve($0, repo: repo) }
        let groups = Dictionary(grouping: resolved) { ShopCategory.category(of: $0) }
        return groups
            .map { ShopCard(category: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { a, b in
                if a.category.isWeapon != b.category.isWeapon { return a.category.isWeapon }
                return a.category.title < b.category.title
            }
    }
}

// MARK: - Display categories (card = category)

/// The shop's card categories. Weapon families feed the top row; the rest feed the
/// rotating bottom row. `advClothes` folds under `.armor` (one cosmetic item, no card
/// of its own).
enum ShopCategory: String, Hashable, CaseIterable {
    case heavyWeapons, heavyOneHanders, finesse, rangedWeapons, smallRanged, magicWeapons
    case armor, shields, potions, magicItems, scrolls, curios

    var isWeapon: Bool {
        switch self {
        case .heavyWeapons, .heavyOneHanders, .finesse, .rangedWeapons, .smallRanged, .magicWeapons: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .heavyWeapons:    "Heavy Weapons"
        case .heavyOneHanders: "Heavy One-Handers"
        case .finesse:         "Finesse Weapons"
        case .rangedWeapons:   "Ranged Weapons"
        case .smallRanged:     "Small Ranged"
        case .magicWeapons:    "Magic Weapons"
        case .armor:           "Armor"
        case .shields:         "Shields"
        case .potions:         "Potions"
        case .magicItems:      "Magic Items"
        case .scrolls:         "Scrolls"
        case .curios:          "Curiosities"
        }
    }

    static func category(of p: Purchasable) -> ShopCategory {
        switch p {
        case .gear(let g):
            switch g.category {
            case .heavyMelee:     return .heavyWeapons
            case .lightMelee:     return g.attack?.toHitStat == .might ? .heavyOneHanders : .finesse
            case .rangedPhysical: return g.attack?.damageStat == nil ? .smallRanged : .rangedWeapons
            case .magicMental:    return .magicWeapons
            case .armor:          return .armor
            case .shield:         return .shields
            case .advClothes:     return .armor
            }
        case .item(let i):
            switch i.kind {
            case .consumable:      return .potions
            case .magicConsumable: return .magicItems
            case .scroll:          return .scrolls
            case .curio:           return .curios
            }
        }
    }
}

/// One category card for the grid. `items` are the specific purchasables currently
/// stocked in this category; the detail screen lists them with prices.
struct ShopCard: Identifiable, Hashable {
    let category: ShopCategory
    let items: [Purchasable]
    var id: ShopCategory { category }
    var title: String { category.title }
    var isWeapon: Bool { category.isWeapon }
}

// MARK: - Restock (the one shop-RNG seam)

extension ShopStock {
    /// Build a fresh shelf: 3 distinct weapon families up top, 3 rotating non-weapon
    /// categories on the bottom, `perCard` items sampled from each — weighted by rarity
    /// so rare/legendary rarely surface.
    static func restocked(from repo: ContentRepository) -> ShopStock {
        var refs: [PurchasableRef] = []

        // How many items each category stocks. Weapons/armor run deep — lots of common
        // gear the player should see often; everything else stays at 2.
        func perCard(_ category: ShopCategory) -> Int {
            switch category {
            case .heavyWeapons, .heavyOneHanders, .finesse, .rangedWeapons, .smallRanged, .magicWeapons: 5
            case .armor: 4
            default: 2
            }
        }

        // Top row: 3 distinct weapon families.
        let weaponGear = repo.allGear().filter { ShopCategory.category(of: .gear($0)).isWeapon }
        let byFamily = Dictionary(grouping: weaponGear) { ShopCategory.category(of: .gear($0)) }
        for family in byFamily.keys.shuffled().prefix(3) {
            let picks = weightedSample(byFamily[family] ?? [], count: perCard(family)) { $0.rarity.weight }
            refs += picks.map { .gear($0.id) }
        }

        // Bottom row: 3 distinct categories from the rotating non-weapon pool.
        let nonWeaponGear = repo.allGear()
            .filter { !ShopCategory.category(of: .gear($0)).isWeapon }
            .map(Purchasable.gear)
        let bottomPool = nonWeaponGear + repo.items().map(Purchasable.item)
        let byCategory = Dictionary(grouping: bottomPool) { ShopCategory.category(of: $0) }
        for category in byCategory.keys.shuffled().prefix(3) {
            let picks = weightedSample(byCategory[category] ?? [], count: perCard(category)) { $0.rarity.weight }
            refs += picks.map { p in
                switch p {
                case .gear(let g): PurchasableRef.gear(g.id)
                case .item(let i): PurchasableRef.item(i.id)
                }
            }
        }

        return ShopStock(refs: refs)
    }
}

/// Weighted sample without replacement — items with higher weight are picked first,
/// more often. File-private free function (not a method) so `restocked`'s static
/// context can call it directly.
private func weightedSample<T>(_ items: [T], count: Int, weight: (T) -> Int) -> [T] {
    var pool = items
    var out: [T] = []
    while out.count < count, !pool.isEmpty {
        let total = pool.reduce(0) { $0 + max(weight($1), 1) }
        var roll = Int.random(in: 0..<total)
        var idx = 0
        for (i, item) in pool.enumerated() {
            roll -= max(weight(item), 1)
            if roll < 0 { idx = i; break }
        }
        out.append(pool.remove(at: idx))
    }
    return out
}

// MARK: - The store

@MainActor
@Observable
final class ShopStore {
    private(set) var stock: ShopStock = .empty
    private(set) var lastRestock: Date = .distantPast

    static let singletonKey = "shop"
    /// Local wall-clock hours the shelf refreshes at (fixed 8 AM / 5 PM, per design).
    static let restockHours = [8, 17]

    private let context: ModelContext

    init(context: ModelContext? = nil) {
        self.context = context ?? PersistenceStore.container.mainContext
        loadFromDisk()
    }

    // MARK: Stock lifecycle

    /// Call when the repo is available (e.g. the shop tab's onAppear). First-stocks an
    /// empty shelf, then catches up any scheduled restocks missed while the app was closed.
    func ensureStocked(repo: ContentRepository, now: Date = .now) {
        if stock.refs.isEmpty {
            restock(repo: repo, now: now)
        } else {
            refreshIfDue(repo: repo, now: now)
        }
    }

    /// Restock now — used by both the schedule and a manual "Restock" debug button.
    func restock(repo: ContentRepository, now: Date = .now) {
        stock = ShopStock.restocked(from: repo)
        lastRestock = now
        persist()
    }

    /// Restock only if a scheduled boundary (8 AM / 5 PM local) has passed since the
    /// last restock. Cheap to call on every appear.
    func refreshIfDue(repo: ContentRepository, now: Date = .now) {
        if lastRestock < Self.mostRecentBoundary(before: now) {
            restock(repo: repo, now: now)
        }
    }

    /// Cards for the grid.
    func cards(repo: ContentRepository) -> [ShopCard] { stock.cards(repo: repo) }

    // MARK: Scheduling

    /// The latest 8 AM / 5 PM local instant at or before `now`.
    static func mostRecentBoundary(before now: Date, calendar: Calendar = .current) -> Date {
        var candidates: [Date] = []
        for dayOffset in [-1, 0] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for hour in restockHours {
                if let d = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) {
                    candidates.append(d)
                }
            }
        }
        return candidates.filter { $0 <= now }.max() ?? now
    }

    // MARK: Persistence (single shared row, upsert by key)

    private func loadFromDisk() {
        guard let row = fetchRow(),
              let decoded = try? JSONDecoder().decode(ShopStock.self, from: row.data) else { return }
        stock = decoded
        lastRestock = row.lastRestock
    }

    private func persist() {
        let data = (try? JSONEncoder().encode(stock)) ?? Data()
        if let row = fetchRow() {
            row.data = data
            row.lastRestock = lastRestock
        } else {
            context.insert(StoredShop(key: Self.singletonKey, lastRestock: lastRestock, data: data))
        }
        try? context.save()
    }

    private func fetchRow() -> StoredShop? {
        let key = Self.singletonKey
        let descriptor = FetchDescriptor<StoredShop>(predicate: #Predicate { $0.key == key })
        return try? context.fetch(descriptor).first
    }
}
