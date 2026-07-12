//  Definitions.swift
//  TinyQuestContent — Codable definitions loaded from JSON, read-only at runtime.
//  A saved character stores *choices*; the sheet is derived from choices + these.
//
//  Canonical as of the character-sheet v2 pass:
//   • Path Powers / Signature Powers are GRANT-ALL (pathPowerIDs / signaturePowerIDs).
//   • Paths can grant LEVEL-1 abilities (coreAbilityIDs): Druid's Quick Cast,
//     Mystic's Reactive Caster, Shadow's Silent Step, Wild's cosmetic pet.
//   • Abilities can be gear-gated (requiresGearCategory): Shield needs a shield.
//   • Companions carry a flat hitBonus (book pets roll d20 + N, not d20 + stat);
//     a companion attack's nil toHitStat means "d20 + hitBonus", not auto-hit.
//   • "Race" stays the internal identifier + JSON key; "Kind" is presentational.
//
//  Bug-fix pass:
//   • signatureBox moved from ClassDefinition to PathDefinition. The gold L3 signature
//     box is now PATH-gated (Wild only), not class-gated (all Scouts) — the playtest
//     answer to "class- vs path-level" was path-level. Opting a path in is a JSON edit,
//     never a code change.

import Foundation

// MARK: - Theme (§9.2). Class-level token, optional Path override (Mystic).

public struct ThemeToken: Codable, Hashable, Sendable {
    public let background: String   // hex
    public let panel: String        // hex (the cream fields)
    public let accent: String       // hex
    public let ink: String          // hex
    public let emblem: String       // motif id: "shield", "spellbook-orb", "tarot", "bow", "sun"
}

// MARK: - Gear

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
    public let effects: [EffectHint]    // default []

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
public struct SpellGrant: Codable, Hashable, Sendable {
    public let spellID: String
    public let readyUses: Int   // default 1

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
    public let affects: Recipient                    // default .selfTarget
    public let attack: AttackProfile?
    public let effects: [EffectHint]                 // default []
    /// Gear gate: unavailable (struck-through, hints inert) unless something of
    /// this category is equipped. Shield -> .shield. Default nil.
    public let requiresGearCategory: GearCategory?

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
        requiresGearCategory = try c.decodeIfPresent(GearCategory.self, forKey: .requiresGearCategory)
    }
}

// MARK: - Companions (the book's named pets; Wild Scout's bonded friend uses the same shape)

public struct CompanionGrowth: Codable, Hashable, Sendable {
    public let name: String
    public let maxHP: Int
    public let attack: AttackProfile?
}

public struct CompanionDefinition: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let maxHP: Int
    /// Flat to-hit bonus ("HP 5 · +3 hit · d6"). Companion attacks with nil
    /// toHitStat mean "d20 + hitBonus", NOT auto-hit (unlike hero attacks).
    public let hitBonus: Int?
    public let attack: AttackProfile?
    public let trick: AbilityDefinition?        // its signature trick
    public let growthStates: [CompanionGrowth]? // Ember grows over a campaign
}

// MARK: - Race ("Kind" in the book/UI). Identity, never math.

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
    public let hpByLevel: [Int]
    public let coreAbilityIDs: [String]
    public let pathIDs: [String]
    public let spellListID: String?
    public let baseSpells: [SpellGrant]
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
    /// The book's recommended kit — seeds the Gear picker and Build Info.
    /// NOT auto-equipped: characters start with Gear blank.
    public let startingGearIDs: [String]
    /// LEVEL-1 abilities specific to this path (default []).
    public let coreAbilityIDs: [String]
    /// GRANT-ALL at L2.
    public let pathPowerIDs: [String]
    /// GRANT-ALL at L3.
    public let signaturePowerIDs: [String]
    public let specialSpells: [String]
    public let startingLoadoutOverride: [SpellGrant]?
    public let themeOverride: ThemeToken?
    /// Render L3 signature powers in their OWN gold box on the sheet (a level-up
    /// moment: the box APPEARS at level 3). Content-gated trial — set true on the
    /// WILD path only for now. Default false/absent.
    public let signatureBox: Bool?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        classID = try c.decode(String.self, forKey: .classID)
        name = try c.decode(String.self, forKey: .name)
        blurb = try c.decode(String.self, forKey: .blurb)
        startingGearIDs = try c.decode([String].self, forKey: .startingGearIDs)
        coreAbilityIDs = try c.decodeIfPresent([String].self, forKey: .coreAbilityIDs) ?? []
        pathPowerIDs = try c.decode([String].self, forKey: .pathPowerIDs)
        signaturePowerIDs = try c.decode([String].self, forKey: .signaturePowerIDs)
        specialSpells = try c.decodeIfPresent([String].self, forKey: .specialSpells) ?? []
        startingLoadoutOverride = try c.decodeIfPresent([SpellGrant].self, forKey: .startingLoadoutOverride)
        themeOverride = try c.decodeIfPresent(ThemeToken.self, forKey: .themeOverride)
        signatureBox = try c.decodeIfPresent(Bool.self, forKey: .signatureBox)
    }
}

// Level-up rule is GLOBAL, not path data: at L2/L3 spend 2 stat points (player picks
// the split — see LevelUpSheet), HP -> hpByLevel[level-1], gain ALL Path Powers (L2)
// / ALL Signature Powers (L3). Dual wield is likewise GLOBAL and derived: two equipped
// lightMelee weapons = a free-action second attack (CharacterSheet.hasDualWield).

// MARK: - The bundle the loader decodes

public struct ContentBundle: Codable, Sendable {
    public let classes: [ClassDefinition]
    public let paths: [PathDefinition]
    public let abilities: [AbilityDefinition]
    public let spells: [SpellDefinition]
    public let spellLists: [SpellListDefinition]
    public let gear: [GearDefinition]
    public let races: [RaceDefinition]
    public let companions: [CompanionDefinition]

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
