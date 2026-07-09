//  CharacterChoices.swift
//  The content-is-data payload: a character is the CHOICES a player made, never a
//  computed sheet. (This is the plain-struct stand-in for the TDD's SavedCharacter;
//  it becomes the SwiftData model in step 4.)
//
//  Design rulings (July 2026 UI reset):
//   • Path Powers and Signature Powers are GRANT-ALL at L2/L3 — not choices.
//   • Gear is a stored choice. The sheet's Gear section starts BLANK; the kid adds
//     items (seeded picker = the path's book kit). Equipped gear drives Max HP,
//     the active weapon profile, and gear-gated abilities (Shield).
//   • Pets, magic items, and normal items are free-form user additions (the loot
//     model may formalize magic items later; strings are fine pre-persistence).
//   • "Race" stays the internal identifier; the book's "Kind" is presentational.

import Foundation

struct PetChoice: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var imageID: String? = nil      // future pet-image gallery slot
}

struct CharacterChoices: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var raceID: String
    var portraitID: String? = nil
    var classID: String
    var pathID: String
    var level: Int = 1
    var statBoosts: [String: Int] = [:]         // stat.rawValue -> total +N from level-ups
    var equippedGearIDs: [String] = []          // Gear section contents; starts empty
    var pets: [PetChoice] = []                  // standard pet: 5 HP, +2 hit / d6
    var magicItems: [String] = []               // free-form until the loot model lands
    var normalItems: [String] = []              // free-form
    var spellbookIDs: [String] = []             // caster: grows via loot
    var readySpellIDs: [String] = []            // caster: cap 6 (8 with Spell Master)
}

// Small convenience the repo protocol didn't ship (lookup a class by id).
extension ContentRepository {
    func klass(_ id: String) -> ClassDefinition? { classes().first { $0.id == id } }
}

// MARK: - Lightweight "what you start with" derivation
// Previews the path's RECOMMENDED book kit (Build Info on the path detail screen).
// It intentionally reads path.startingGearIDs — the offer, not equipped state.

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
