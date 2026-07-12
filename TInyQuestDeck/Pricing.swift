//  Pricing.swift
//  The shop economy in one place. A single `Rarity` axis on gear + items drives BOTH
//  how often something appears (restock weight) AND which price column it sits in — so
//  adding content is mostly "name it, set its rarity, done."
//
//  Price = explicit `cost` if the content sets one, else Pricing.base(group, rarity).
//  Tune the whole economy from the two tables below; nothing else hard-codes numbers.

import Foundation

/// How rare a purchasable is. Sets appearance odds and the price band.
///  • common    — base gear / basic potions. Rotates freely.
///  • uncommon  — "customized"-look gear, tier-1 magic items & scrolls. Rotates freely.
///  • rare      — tier-2. ~15% as likely to appear. Super rare.
///  • legendary — tier-3. Almost never.
public enum Rarity: String, Codable, Sendable, CaseIterable {
    case common, uncommon, rare, legendary

    /// Relative restock weight. Lower the tiers here to make them globally rarer.
    public var weight: Int {
        switch self {
        case .common:    100
        case .uncommon:  100   // rotates with normal gear, per design
        case .rare:       15   // ~15% of the time
        case .legendary:   2   // almost never
        }
    }
}

public enum Pricing {
    /// Price bands. Row = the item's family, column = its rarity.
    public enum Group: Hashable { case weapon, armor, potion, magic, scroll }

    private static let matrix: [Group: [Rarity: Int]] = [
        .weapon: [.common: 50,  .uncommon: 100,  .rare: 250,  .legendary: 500],
        .armor:  [.common: 50,  .uncommon: 100,  .rare: 250,  .legendary: 500],
        .potion: [.common: 200, .uncommon: 350,  .rare: 700,  .legendary: 1500],
        .magic:  [.common: 500, .uncommon: 1000, .rare: 2500, .legendary: 6000],
        .scroll: [.common: 500, .uncommon: 1000, .rare: 2500, .legendary: 6000],
    ]

    public static func base(_ group: Group, _ rarity: Rarity) -> Int {
        matrix[group]?[rarity] ?? 0
    }

    /// Gear splits into weapon vs. defensive (armor / shields / clothes).
    public static func group(for category: GearCategory) -> Group {
        switch category {
        case .heavyMelee, .lightMelee, .rangedPhysical, .magicMental: .weapon
        case .armor, .shield, .advClothes:                            .armor
        }
    }

    /// Item kind also picks the price band: potions vs. magic items vs. scrolls.
    public static func group(for kind: ItemKind) -> Group {
        switch kind {
        case .consumable:      .potion
        case .magicConsumable: .magic
        case .scroll:          .scroll
        }
    }
}
