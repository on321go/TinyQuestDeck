//  CharacterChoices.swift
//  The content-is-data payload: a character is the CHOICES a player made, never a
//  computed sheet. (This is the plain-struct stand-in for the TDD's SavedCharacter;
//  it becomes the SwiftData model in step 4.)
//
//  Level-up fields are here so the model is complete, but the Part-1 builder only sets
//  the Level-1 ones (name / race / class / path + seeded starting spells). Stat boosts,
//  path power, and signature get filled in when leveling lands.

import Foundation

struct CharacterChoices: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var raceID: String
    var classID: String
    var pathID: String
    var level: Int = 1
    var statBoosts: [String: Int] = [:]        // stat.rawValue -> total +N from level-ups
    var chosenPathPowerID: String? = nil        // set at L2 (auto for single-option paths)
    var chosenSignatureID: String? = nil        // set at L3
    var spellbookIDs: [String] = []             // caster: grows via loot
    var readySpellIDs: [String] = []            // caster: cap 6 (8 with Spell Master)
}

// Small convenience the repo protocol didn't ship (lookup a class by id).
extension ContentRepository {
    func klass(_ id: String) -> ClassDefinition? { classes().first { $0.id == id } }
}

// MARK: - Lightweight "what you start with" derivation
// A taste of the full sheet derivation (step 3) — enough to preview in the builder and
// show on a hero's summary. Pure function over the repo; trivially testable.

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

    let gear = path.startingGearIDs.compactMap { repo.gear($0) }
    let level = max(1, min(c.level, cls.hpByLevel.count))
    let hp = cls.hpByLevel[level - 1] + gear.reduce(0) { $0 + $1.maxHP }
    func stat(_ s: Stat) -> Int { cls.baseStats[s] + (c.statBoosts[s.rawValue] ?? 0) }

    let spells = startingGrants(classID: c.classID, pathID: c.pathID, repo: repo)
        .compactMap { g -> StartingSpell? in
            guard let s = repo.spell(g.spellID) else { return nil }
            return StartingSpell(name: s.name, uses: g.readyUses)
        }

    return StartingSummary(
        raceName: race.name, className: cls.name, pathName: path.name,
        might: stat(.might), mind: stat(.mind), speed: stat(.speed),
        hp: hp, gearNames: gear.map(\.name), spells: spells)
}
