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
    var pets: [PetChoice] = []
    var magicItems: [String] = []
    var normalItems: [String] = []
    var spellbookIDs: [String] = []             // all known spells
    var readySpellIDs: [String] = []            // subset; cap 6 (8 with Spell Master)
    /// Druid's Voice-of-the-Wild spirit animal art (spirit-image gallery slot,
    /// "2" -> spirit-2). Persists across summons/Rests — a character trait, not
    /// live combat state. nil = default (spirit-1).
    var spiritImageID: String? = nil
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
