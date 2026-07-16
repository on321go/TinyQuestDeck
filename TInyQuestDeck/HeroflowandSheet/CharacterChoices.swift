//  CharacterChoices.swift
//  The content-is-data payload: a character is the CHOICES a player made, never a
//  computed sheet. Becomes the SwiftData model in step 4.
//
//  Rulings: grant-all powers (no choice fields); blank-start equipped gear; pets
//  reference a book companion (companionID) or are custom (nil = standard 5 HP,
//  +2 hit, d6); magic/normal items are free-form strings pre-loot-model.

import Foundation

struct PetChoice: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var companionID: String? = nil   // book companion; nil = custom standard pet
    var imageID: String? = nil       // pet-image gallery slot ("3" -> pet-3)
}

struct CharacterChoices: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var raceID: String
    var portraitID: String? = nil
    var classID: String
    var pathID: String
    var level: Int = 1
    var statBoosts: [String: Int] = [:]
    var equippedGearIDs: [String] = []          // Gear box; starts empty; cap 5 (UI rule)
    /// Gear the hero OWNS but hasn't necessarily equipped (buy = own). Purchases land
    /// here; the equip flow reads it later. Inert until equip-from-owned is wired — the
    /// sheet's Add-gear menu still offers the full catalog for now.
    var ownedGearIDs: [String] = []
    var pets: [PetChoice] = []
    var magicItems: [String] = []
    var normalItems: [String] = []
    var spellbookIDs: [String] = []             // all known spells
    var readySpellIDs: [String] = []            // subset; cap 6 (8 with Spell Master)
    /// Druid's Voice-of-the-Wild spirit animal art (spirit-image gallery slot,
    /// "2" -> spirit-2). Persists across summons/Rests — a character trait, not
    /// live combat state. nil = default (spirit-1).
    var spiritImageID: String? = nil
    /// Wallet — the hero's spendable gold (the shop's only currency). Defaults to 0 so
    /// every existing construction site AND every saved hero stays valid: no migration,
    /// no delete-and-relaunch.
    var gold: Int = 100      // starting budget to customize; earn more to diversify
    /// Stars — the progression currency (never "XP"). Earned in milestone-sized chunks:
    /// quest/boss stars party-wide, a rare individual GM bonus star. 3 → Level 2,
    /// 6 → Level 3 (see `starThresholds`). NOT capped at 6: extras accumulate quietly
    /// for levels that don't exist yet, per the spec's "add thresholds later, never
    /// dilute existing ones." Same default-0 migration story as gold.
    var stars: Int = 0
    var showcaseGearIDs: [String] = []   // up to 3 gear pieces the kid shows off
    var showcaseItemIDs: [String] = []   // up to 3 items the kid shows off
}

extension CharacterChoices {
    // Migration-safe decode. Swift's SYNTHESIZED Decodable ignores property defaults for
    // non-optional fields and throws keyNotFound on a missing key — so adding a stored
    // field would invalidate every hero blob saved before that field existed. Decoding
    // each field with `decodeIfPresent(...) ?? <default>` instead means a newly-added
    // field simply reads as its default on old blobs, and nothing gets dropped.
    //
    // Kept in an EXTENSION so the automatic memberwise initializer (used by the creation
    // flow) survives. CodingKeys and encode(to:) are still synthesized, so new fields
    // round-trip automatically once added above — just add the matching line here.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decodeIfPresent(UUID.self,           forKey: .id) ?? UUID()
        name            = try c.decodeIfPresent(String.self,         forKey: .name) ?? ""
        raceID          = try c.decodeIfPresent(String.self,         forKey: .raceID) ?? ""
        portraitID      = try c.decodeIfPresent(String.self,         forKey: .portraitID)
        classID         = try c.decodeIfPresent(String.self,         forKey: .classID) ?? ""
        pathID          = try c.decodeIfPresent(String.self,         forKey: .pathID) ?? ""
        level           = try c.decodeIfPresent(Int.self,            forKey: .level) ?? 1
        statBoosts      = try c.decodeIfPresent([String: Int].self,  forKey: .statBoosts) ?? [:]
        equippedGearIDs = try c.decodeIfPresent([String].self,       forKey: .equippedGearIDs) ?? []
        ownedGearIDs    = try c.decodeIfPresent([String].self,       forKey: .ownedGearIDs) ?? []
        pets            = try c.decodeIfPresent([PetChoice].self,     forKey: .pets) ?? []
        magicItems      = try c.decodeIfPresent([String].self,       forKey: .magicItems) ?? []
        normalItems     = try c.decodeIfPresent([String].self,       forKey: .normalItems) ?? []
        spellbookIDs    = try c.decodeIfPresent([String].self,       forKey: .spellbookIDs) ?? []
        readySpellIDs   = try c.decodeIfPresent([String].self,       forKey: .readySpellIDs) ?? []
        spiritImageID   = try c.decodeIfPresent(String.self,         forKey: .spiritImageID)
        gold            = try c.decodeIfPresent(Int.self,            forKey: .gold) ?? 100
        stars           = try c.decodeIfPresent(Int.self,            forKey: .stars) ?? 0
        showcaseGearIDs = try c.decodeIfPresent([String].self, forKey: .showcaseGearIDs) ?? []
        showcaseItemIDs = try c.decodeIfPresent([String].self, forKey: .showcaseItemIDs) ?? []
    }
}

// MARK: - Stars → levels (pure, derived — nothing stored but the count)

extension CharacterChoices {
    /// Stars needed to REACH each level: index 0 → Level 2, index 1 → Level 3.
    /// One no-reset track, so these are cumulative totals, not per-level costs.
    /// Levels 4+ would append here (e.g. 10) — never re-price 3 and 6.
    static let starThresholds = [3, 6]

    /// How many slots the track draws. Stars past this still count (see `stars`);
    /// they just have nowhere to show yet.
    static var starTrackLength: Int { starThresholds.last ?? 6 }

    /// The level this hero's stars entitle them to. Levels are CLAIMED, not granted —
    /// the kid still spends their 2 points in the level-up flow — so this is only ever
    /// compared against `level`, never assigned to it.
    var earnedLevel: Int {
        1 + Self.starThresholds.filter { stars >= $0 }.count
    }

    /// True when the level badge should light up: the stars are in the bank and the
    /// hero hasn't spent them yet. Drives the badge, not the leveling itself.
    var canLevelUp: Bool { earnedLevel > level }

    /// Stars still needed for the next level; nil once every threshold is passed.
    var starsToNextLevel: Int? {
        guard let next = Self.starThresholds.first(where: { $0 > stars }) else { return nil }
        return next - stars
    }
}

// Small convenience the repo protocol didn't ship (lookup a class by id).
extension ContentRepository {
    func klass(_ id: String) -> ClassDefinition? { classes().first { $0.id == id } }
}

// MARK: - "What you start with" preview (Build Info on the path detail screen)

struct StartingSpell: Hashable { let name: String; let uses: Int }

struct StartingSummary: Hashable {
    var raceName: String
    var className: String
    var pathName: String
    var might: Int
    var mind: Int
    var speed: Int
    var hp: Int
    var gearNames: [String]
    var spells: [StartingSpell]
}

/// The grants a fresh character starts with: path override if present, else class default.
func startingGrants(classID: String, pathID: String, repo: ContentRepository) -> [SpellGrant] {
    let override = repo.path(pathID)?.startingLoadoutOverride
    return override ?? repo.klass(classID)?.baseSpells ?? []
}

func startingSummary(for c: CharacterChoices, using repo: ContentRepository) -> StartingSummary? {
    guard let cls = repo.klass(c.classID),
          let path = repo.path(c.pathID),
          let race = repo.race(c.raceID) else { return nil }

    let kit = path.startingGearIDs.compactMap { repo.gear($0) }
    let level = max(1, min(c.level, cls.hpByLevel.count))
    let hp = cls.hpByLevel[level - 1] + kit.reduce(0) { $0 + $1.maxHP }
    func stat(_ s: Stat) -> Int { cls.baseStats[s] + (c.statBoosts[s.rawValue] ?? 0) }

    let spells = startingGrants(classID: c.classID, pathID: c.pathID, repo: repo)
        .compactMap { g -> StartingSpell? in
            guard let s = repo.spell(g.spellID) else { return nil }
            return StartingSpell(name: s.name, uses: g.readyUses)
        }

    return StartingSummary(
        raceName: race.name, className: cls.name, pathName: path.name,
        might: stat(.might), mind: stat(.mind), speed: stat(.speed),
        hp: hp, gearNames: kit.map(\.name), spells: spells)
}
