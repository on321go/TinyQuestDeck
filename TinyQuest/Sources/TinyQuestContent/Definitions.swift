//  Definitions.swift
//  TinyQuestContent — Codable definitions loaded from JSON, read-only at runtime.
//  A saved character stores *choices*; the sheet is derived from choices + these.

import Foundation
import TinyQuestKit

// MARK: - Theme (§9.2). Class-level token, optional Path override (Mystic).

public struct ThemeToken: Codable, Hashable, Sendable {
    public let background: String   // hex
    public let panel: String        // hex (the cream fields)
    public let accent: String       // hex
    public let ink: String          // hex
    public let emblem: String       // motif id: "shield", "spellbook-orb", "tarot", "bow"
}

// MARK: - Gear (weapon categories + armor/shield/clothes; named loot items slot in later, same shape)

public enum GearCategory: String, Codable, Sendable {
    case heavyMelee, lightMelee, rangedPhysical, magicMental
    case armor, shield, advClothes
}

public struct GearDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: GearCategory
    public let attack: AttackProfile?   // nil for armor/shield/clothes
    public let maxHP: Int               // default 0

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(GearCategory.self, forKey: .category)
        attack = try c.decodeIfPresent(AttackProfile.self, forKey: .attack)
        maxHP = try c.decodeIfPresent(Int.self, forKey: .maxHP) ?? 0
    }
}

// MARK: - Spells

public enum SpellTier: String, Codable, Sendable { case core, t1, t2, t3 }

public struct SpellDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let tier: SpellTier
    public let text: String
    public let attack: AttackProfile?   // nil = utility
    public let effects: [EffectHint]    // on-hit conditions etc.; default []  [ADDED]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tier = try c.decode(SpellTier.self, forKey: .tier)
        text = try c.decode(String.self, forKey: .text)
        attack = try c.decodeIfPresent(AttackProfile.self, forKey: .attack)
        effects = try c.decodeIfPresent([EffectHint].self, forKey: .effects) ?? []
    }
}

public struct SpellListDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let spellIDs: [String]   // the catalog a caster can ever draw from
}

/// A starting/granted spell carries its own Ready cast-count (the ☐ boxes).
/// Path-specific, not intrinsic: Cleric grants Bless×2, Mystic grants Bless×1.
public struct SpellGrant: Codable, Hashable, Sendable {
    public let spellID: String
    public let readyUses: Int   // default 1 (box-less spells = 1 cast/Rest)

    public init(spellID: String, readyUses: Int = 1) {
        self.spellID = spellID; self.readyUses = readyUses
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spellID = try c.decode(String.self, forKey: .spellID)
        readyUses = try c.decodeIfPresent(Int.self, forKey: .readyUses) ?? 1
    }
}

// MARK: - Abilities

public struct AbilityDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let text: String
    public let actionCost: ActionCost
    public let reset: ResetTrigger
    public let affects: Recipient         // default .selfTarget
    public let attack: AttackProfile?     // damage-dealing powers (Fire Explosion)  [ADDED]
    public let effects: [EffectHint]      // default []

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        text = try c.decode(String.self, forKey: .text)
        actionCost = try c.decode(ActionCost.self, forKey: .actionCost)
        reset = try c.decode(ResetTrigger.self, forKey: .reset)
        affects = try c.decodeIfPresent(Recipient.self, forKey: .affects) ?? .selfTarget
        attack = try c.decodeIfPresent(AttackProfile.self, forKey: .attack)
        effects = try c.decodeIfPresent([EffectHint].self, forKey: .effects) ?? []
    }
}

// MARK: - Companions (designed now; instances encoded later. Acts at end of round.)

public struct CompanionGrowth: Codable, Hashable, Sendable {
    public let name: String
    public let maxHP: Int
    public let attack: AttackProfile?
}

public struct CompanionDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let maxHP: Int
    public let attack: AttackProfile?          // reuses the shared shape
    public let trick: AbilityDefinition?       // reuses ability shape (its signature trick)
    public let growthStates: [CompanionGrowth]? // Ember the Whelpling grows over a campaign
}

// MARK: - Race ("Kind"). Identity, never math. Ability usually narrative (effects: []).

public struct RaceDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let tagline: String
    public let lore: String
    public let appearance: [String]
    public let nameIdeas: [String]
    public let ability: AbilityDefinition
}

// MARK: - Class & Path

public struct ClassDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let role: String
    public let baseStats: StatMap
    public let hpByLevel: [Int]            // class-uniform across paths: Knight [15,20,25]
    public let coreAbilityIDs: [String]
    public let pathIDs: [String]
    public let spellListID: String?        // nil for non-casters
    public let baseSpells: [SpellGrant]    // default [] (non-casters); the default loadout
    public let theme: ThemeToken

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        role = try c.decode(String.self, forKey: .role)
        baseStats = try c.decode(StatMap.self, forKey: .baseStats)
        hpByLevel = try c.decode([Int].self, forKey: .hpByLevel)
        coreAbilityIDs = try c.decodeIfPresent([String].self, forKey: .coreAbilityIDs) ?? []
        pathIDs = try c.decode([String].self, forKey: .pathIDs)
        spellListID = try c.decodeIfPresent(String.self, forKey: .spellListID)
        baseSpells = try c.decodeIfPresent([SpellGrant].self, forKey: .baseSpells) ?? []
        theme = try c.decode(ThemeToken.self, forKey: .theme)
    }
}

public struct PathDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let classID: String
    public let name: String
    public let blurb: String
    public let startingGearIDs: [String]
    /// L2 power. Single-element = auto-selected; multi = pick-one (Wizard, mirrors L3 signature).
    public let pathPowerOptionIDs: [String]
    public let signatureOptionIDs: [String]       // pick one at L3
    public let specialSpells: [String]            // thematic/accessible pool (IDs), not grants
    /// Replaces ClassDefinition.baseSpells when present (Mystic drops Animal Friend, adds Dispel).
    /// nil for both Wizard paths -> they use the class default loadout.
    public let startingLoadoutOverride: [SpellGrant]?
    public let themeOverride: ThemeToken?         // Mystic

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        classID = try c.decode(String.self, forKey: .classID)
        name = try c.decode(String.self, forKey: .name)
        blurb = try c.decode(String.self, forKey: .blurb)
        startingGearIDs = try c.decode([String].self, forKey: .startingGearIDs)
        pathPowerOptionIDs = try c.decode([String].self, forKey: .pathPowerOptionIDs)
        signatureOptionIDs = try c.decode([String].self, forKey: .signatureOptionIDs)
        specialSpells = try c.decodeIfPresent([String].self, forKey: .specialSpells) ?? []
        startingLoadoutOverride = try c.decodeIfPresent([SpellGrant].self, forKey: .startingLoadoutOverride)
        themeOverride = try c.decodeIfPresent(ThemeToken.self, forKey: .themeOverride)
    }

    /// Convenience for the builder: single-option paths auto-select their L2 power.
    public var autoSelectedPathPowerID: String? {
        pathPowerOptionIDs.count == 1 ? pathPowerOptionIDs.first : nil
    }
}

// Level-up rule is GLOBAL, not path data: at L2 and L3, boost one stat by +2 (player picks),
// bump HP to ClassDefinition.hpByLevel[level-1], gain Path Power (L2) / Signature (L3).
// Recorded as the kid's *choices* on SavedCharacter, so no per-path levelTrack is needed.

// MARK: - The bundle the loader decodes (single content.json for M1)

public struct ContentBundle: Codable, Sendable {
    public let classes: [ClassDefinition]
    public let paths: [PathDefinition]
    public let abilities: [AbilityDefinition]
    public let spells: [SpellDefinition]
    public let spellLists: [SpellListDefinition]
    public let gear: [GearDefinition]
    public let races: [RaceDefinition]
    public let companions: [CompanionDefinition]   // empty this pass

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        classes = try c.decode([ClassDefinition].self, forKey: .classes)
        paths = try c.decode([PathDefinition].self, forKey: .paths)
        abilities = try c.decode([AbilityDefinition].self, forKey: .abilities)
        spells = try c.decode([SpellDefinition].self, forKey: .spells)
        spellLists = try c.decode([SpellListDefinition].self, forKey: .spellLists)
        gear = try c.decode([GearDefinition].self, forKey: .gear)
        races = try c.decode([RaceDefinition].self, forKey: .races)
        companions = try c.decodeIfPresent([CompanionDefinition].self, forKey: .companions) ?? []
    }
}
